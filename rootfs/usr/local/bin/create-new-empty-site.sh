#!/bin/bash -e

if ! command -V pwgen >/dev/null 2>&1; then
  apt-get -q update
  apt-get -yq install pwgen
fi

DB_PASSWORD=kahNgooj1eed4siech
CREATED_AT=${1}
DOMAIN=$(echo $2 | sed "s/http://g" | sed "s/https://g" | sed "s/\///g")
createMySQLDatabase=${3:-"false"}
APP_DB_HOST=${4:-"mysql"}
APP_DB_PORT=${5:-"3306"}
APP_DB_NAME=${6:-$(echo ${DOMAIN} | tr '.' '_')}
APP_DB_USER=${7:-${APP_DB_NAME}}
APP_DB_PASSWORD=${8:-$(pwgen 20 1)}

DOCROOT_FOLDER=/var/www/public/${DOMAIN}

if [ a${DOMAIN} == "a" ]; then
  echo "ERROR: Empty domain, please specify a domain. Usage: $0 yourdomain.com"
  exit 1
fi

if [ -e ${DOCROOT_FOLDER} ]; then
  echo "ERROR: website for domain ${DOMAIN} already exists on ${DOCROOT_FOLDER} folder - Aborting ..."
  exit 1
fi

echo "Creating site for domain ${DOMAIN} ..."
[ a"${createMySQLDatabase}" == a"true" ] && `dirname $0`/create-new-mysql-db.sh "${CREATED_AT}" "${APP_DB_NAME}" "${APP_DB_USER}" "${APP_DB_PASSWORD}"
mkdir -p ${DOCROOT_FOLDER}/www
pushd $(dirname ${DOCROOT_FOLDER}) >/dev/null
ln -s ${DOMAIN} www.${DOMAIN}
popd >/dev/null
[ a"${CREATED_AT}" != "a" ] && echo "Site created with <a href=\"https://solidwp.host\">solidwp.host</a> in just $((`date +%s`-${CREATED_AT})) seconds!<br><br>Connect to your site via SFTP to add your files." > ${DOCROOT_FOLDER}/index.html
echo "Creation of site for domain ${DOMAIN} finished"

