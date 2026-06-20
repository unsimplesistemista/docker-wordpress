#!/bin/bash
set -uo pipefail

SITES_DIR="/var/www/public"
SOCK_DIR="/run/php-fpm"
TMP_BASE="/tmp/php-fpm"
LOG_DIR="/var/log/php-fpm"
CHANGED=0

DOMAIN=""
FORCE=0
while getopts "d:f" opt; do
    case "$opt" in
        d) DOMAIN="$OPTARG" ;;
        f) FORCE=1 ;;
        *) echo "Usage: $0 [-d domain] [-f]" >&2; exit 1 ;;
    esac
done

LOCK_FILE="${SITES_DIR}/.setup-site-isolation.lock"
exec 9>"$LOCK_FILE"
SKIP_CHOWN=0
if ! flock -n 9; then
    echo "[site-isolation] another instance running, skipping chown/chmod" >&2
    SKIP_CHOWN=1
fi

# Detect active PHP version
PHP_VERSION=$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;' 2>/dev/null)
if [ -z "$PHP_VERSION" ]; then
    echo "[site-isolation] ERROR: could not detect PHP version" >&2
    exit 1
fi

POOL_DIR="/etc/php/${PHP_VERSION}/fpm/pool.d"
if [ ! -d "$POOL_DIR" ]; then
    echo "[site-isolation] ERROR: pool.d not found at ${POOL_DIR}" >&2
    exit 1
fi

mkdir -p "$SOCK_DIR" "$LOG_DIR"

if [ -n "$DOMAIN" ]; then
    SITE_PATH="${SITES_DIR}/${DOMAIN}"
    if [ ! -d "$SITE_PATH" ]; then
        echo "[site-isolation] ERROR: site directory not found: ${SITE_PATH}" >&2
        exit 1
    fi
    SITE_PATHS="$SITE_PATH"
else
    SITE_PATHS=$(find "$SITES_DIR" -mindepth 1 -maxdepth 1 -type d)
fi

for SITE_PATH in $SITE_PATHS; do
    SITE=$(basename "$SITE_PATH")

    # Sanitize: Linux usernames must be <=32 chars, alphanumeric + underscore only
    USERNAME=$(echo "$SITE" | tr '.-' '__' | tr -cd '[:alnum:]_' | cut -c1-32)

    POOL_CONF="${POOL_DIR}/${SITE}.conf"
    SOCK_PATH="${SOCK_DIR}/${SITE}.sock"
    TMP_DIR="${TMP_BASE}/${SITE}"

    # 1a. Create system user (runs on every start; fast, no filesystem writes)
    # UID is derived deterministically from the site name so it survives container
    # restarts without drift, even when /etc/passwd is ephemeral. 8 hex chars of
    # MD5 give ~4.1B slots (100000–4100099999); birthday collision probability is
    # ~0.012% at 1000 sites and ~1.2% at 10000 sites.
    SITE_UID=$(( ( 0x$(printf '%s' "$SITE" | md5sum | cut -c1-8) % 4100000000 ) + 100000 ))
    if ! id "$USERNAME" &>/dev/null; then
        /usr/sbin/useradd --no-create-home --shell /usr/sbin/nologin \
                --uid "$SITE_UID" "$USERNAME"
        echo "[site-isolation] Created user: ${USERNAME} (uid=${SITE_UID}) for site: ${SITE}"
        CHANGED=1
    fi

    # 1b. Apply ownership and permissions when the site dir isn't already owned by
    # this user. Contents are updated first; SITE_PATH itself is chowned last so
    # its UID acts as a commit marker — a mid-run restart re-triggers this block.
    # Dirs get g+s (setgid) so files created by PHP-FPM inherit group www-data,
    # letting nginx read them via group bits without needing other=r.
    NEEDS_CHOWN=0
    if [ "$FORCE" -eq 1 ]; then
        NEEDS_CHOWN=1
    elif [ "$SKIP_CHOWN" -eq 0 ] && [ "$(stat -c '%u' "$SITE_PATH"/www)" != "$(id -u "$USERNAME")" ]; then
        NEEDS_CHOWN=1
    fi

    if [ "$NEEDS_CHOWN" -eq 1 ]; then
        find "$SITE_PATH"/www -mindepth 1 -exec chown "${USERNAME}:www-data" {} +
        find "$SITE_PATH"/www -mindepth 1 -type f -exec chmod u=rwX,g=rX,o= {} +
        find "$SITE_PATH"/www -mindepth 1 -type d -exec chmod u=rwx,g=rxs,o= {} +
        chmod u=rwx,g=rxs,o= "$SITE_PATH"
        chown root:root "$SITE_PATH"
        chmod 755 "$SITE_PATH"
        chown www-data:www-data "$SITE_PATH"/log
        chown "${USERNAME}:www-data" "$SITE_PATH"/www
        echo "[site-isolation] Applied permissions for: ${SITE}"
    fi

    # 2. Create isolated tmp directories
    if [ ! -d "$TMP_DIR" ]; then
        mkdir -p "${TMP_DIR}/sessions" "${TMP_DIR}/upload"
        chown -R "${USERNAME}:${USERNAME}" "$TMP_DIR"
        chmod 700 "$TMP_DIR"
    fi

    # 3. Create PHP-FPM pool config
    if [ ! -f "$POOL_CONF" ]; then
        cat > "$POOL_CONF" <<EOF
[${SITE}]
user  = ${USERNAME}
group = ${USERNAME}

listen       = ${SOCK_PATH}
listen.owner = \${USER}
listen.group = \${USER}
listen.mode  = 0660

; Spawn workers only on demand — idle sites cost zero memory
pm                      = ondemand
pm.max_children         = \${FPM_PM_MAX_CHILDREN}
pm.process_idle_timeout = \${FPM_PM_PROCESS_IDLE_TIMEOUT}
pm.max_requests         = \${FPM_PM_MAX_REQUESTS}
pm.status_path          = /status

; Restrict PHP to this site's webroot only
php_admin_value[open_basedir]      = ${SITE_PATH}:${TMP_DIR}:/dev/fd/
php_admin_value[upload_tmp_dir]    = ${TMP_DIR}/upload
php_admin_value[session.save_path] = ${TMP_DIR}/sessions
php_admin_value[error_log]         = /dev/fd/2

include = \${PHP_ENV_FILE}
EOF
        echo "[site-isolation] Created FPM pool: ${POOL_CONF}"
        CHANGED=1
    fi
done

# Graceful PHP-FPM reload (USR2) if anything changed
if [ "$CHANGED" -eq 1 ]; then
    FPM_PID=/var/run/php-fpm.pid
    if [ -f "$FPM_PID" ]; then
        kill -USR2 "$(cat "$FPM_PID")" && echo "[site-isolation] PHP-FPM reloaded (USR2)"
    else
        echo "[site-isolation] WARNING: PHP-FPM pid file not found at ${FPM_PID}" >&2
    fi
fi
