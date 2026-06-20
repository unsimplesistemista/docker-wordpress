#!/bin/bash -e

# WORKAROUND
rm -f /etc/apt/sources.list.d/ondrej-ubuntu-nginx-mainline-focal.list

if ! command -V pwgen >/dev/null 2>&1; then
  apt-get -q update
  apt-get -yq install pwgen
fi

DB_PASSWORD=kahNgooj1eed4siech
CREATED_AT=${1}
DOMAIN=$(echo $2 | sed "s/http://g" | sed "s/https://g" | sed "s/\///g")
APP_DB_HOST=${3:-"mysql"}
APP_DB_PORT=${4:-"3306"}
APP_DB_NAME=${5:-$(echo ${DOMAIN} | tr '.' '_')}
APP_DB_USER=${6:-${APP_DB_NAME}}
APP_DB_PASSWORD=${7:-$(pwgen 20 1)}
APP_ADMIN_USER=${8:-"admin"}
APP_ADMIN_PASSWORD=${9:-`pwgen 20 1`}
APP_ADMIN_EMAIL=${10:-"webs@virality.media"}

DOCROOT_FOLDER=/var/www/public/${DOMAIN}/www

if [ a${DOMAIN} == "a" ]; then
  echo "ERROR: Empty domain, please specify a domain. Usage: $0 yourdomain.com"
  exit 1
fi

if [ -e ${DOCROOT_FOLDER} ]; then
  echo "ERROR: website for domain ${DOMAIN} already exists on ${DOCROOT_FOLDER} folder - Aborting ..."
  exit 1
fi

echo "Creating Wordpress installation for domain ${DOMAIN} ..."
`dirname $0`/create-new-empty-site.sh "${CREATED_AT}" "${DOMAIN}"
`dirname $0`/create-new-mysql-db.sh "${CREATED_AT}" "${APP_DB_NAME}" "${APP_DB_USER}" "${APP_DB_PASSWORD}"
wp --allow-root core download --path=${DOCROOT_FOLDER}
wp --allow-root core config --path=${DOCROOT_FOLDER} --dbname=${APP_DB_NAME} --dbuser=${APP_DB_USER} --dbpass=${APP_DB_PASSWORD} --dbhost=${APP_DB_HOST}
wp --allow-root core install --path=${DOCROOT_FOLDER} --url=${DOMAIN} --title="${DOMAIN}" --admin_user=${APP_ADMIN_USER} --admin_password=${APP_ADMIN_PASSWORD} --admin_email=${APP_ADMIN_EMAIL}
wp --allow-root --path=${DOCROOT_FOLDER} user update ${APP_ADMIN_USER} --user_pass=${APP_ADMIN_PASSWORD}
wp --allow-root --path=${DOCROOT_FOLDER} language core install es_ES
rm -f ${DOCROOT_FOLDER}/index.html
/usr/local/bin/setup-site-isolation.sh -d ${DOMAIN} -f
echo "Wordpress installation for domain ${DOMAIN} finished"

