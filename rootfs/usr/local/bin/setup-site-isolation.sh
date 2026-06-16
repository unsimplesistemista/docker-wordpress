#!/bin/bash
set -uo pipefail

SITES_DIR="/var/www/public"
SOCK_DIR="/run/php-fpm"
TMP_BASE="/tmp/php-fpm"
LOG_DIR="/var/log/php-fpm"
CHANGED=0

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

for SITE_PATH in $(find "$SITES_DIR" -mindepth 1 -maxdepth 1 -type d); do
    SITE=$(basename "$SITE_PATH")

    # Sanitize: Linux usernames must be <=32 chars, alphanumeric + underscore only
    USERNAME=$(echo "$SITE" | tr '.-' '__' | tr -cd '[:alnum:]_' | cut -c1-32)

    POOL_CONF="${POOL_DIR}/${SITE}.conf"
    SOCK_PATH="${SOCK_DIR}/${SITE}.sock"
    TMP_DIR="${TMP_BASE}/${SITE}"

    # 1a. Create system user (runs on every start; fast, no filesystem writes)
    if ! id "$USERNAME" &>/dev/null; then
        useradd --no-create-home --shell /usr/sbin/nologin --system "$USERNAME"
        echo "[site-isolation] Created user: ${USERNAME} for site: ${SITE}"
        CHANGED=1
    fi

    # 1b. Apply ownership and permissions when the site dir isn't already owned by
    # this user. Comparing UIDs (not names) catches the case where the container
    # restarted and useradd assigned a different UID to the same username.
    if [ "$(stat -c '%u' "$SITE_PATH")" != "$(id -u "$USERNAME")" ]; then
        chown -R "${USERNAME}:www-data" "$SITE_PATH"
        chmod -R u=rwX,g=rX,o= "$SITE_PATH"
        find "$SITE_PATH" -type d \( -name "uploads" -o -name "cache" -o -name "upgrade" \) \
            -exec chmod g+w {} +
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
listen.owner = www-data
listen.group = www-data
listen.mode  = 0660

; Spawn workers only on demand — idle sites cost zero memory
pm                      = ondemand
pm.max_children         = 10
pm.process_idle_timeout = 10s
pm.max_requests         = 500

; Restrict PHP to this site's webroot only
php_admin_value[open_basedir]      = ${SITE_PATH}:${TMP_DIR}
php_admin_value[upload_tmp_dir]    = ${TMP_DIR}/upload
php_admin_value[session.save_path] = ${TMP_DIR}/sessions
php_admin_value[error_log]         = ${LOG_DIR}/${SITE}.error.log
EOF
        echo "[site-isolation] Created FPM pool: ${POOL_CONF}"
        CHANGED=1
    fi
done

# Graceful PHP-FPM reload (USR2) if anything changed
if [ "$CHANGED" -eq 1 ]; then
    FPM_PID_FILE=$(find /run /var/run -name "php*fpm*.pid" 2>/dev/null | head -1)
    if [ -n "$FPM_PID_FILE" ] && [ -f "$FPM_PID_FILE" ]; then
        kill -USR2 "$(cat "$FPM_PID_FILE")" && \
            echo "[site-isolation] PHP-FPM reloaded (USR2)"
    else
        echo "[site-isolation] WARNING: PHP-FPM pid file not found — pool will load on next FPM start"
    fi
fi
