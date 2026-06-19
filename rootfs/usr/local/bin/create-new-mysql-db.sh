#!/bin/bash -e

if ! command -V pwgen >/dev/null 2>&1; then
  apt-get -q update
  apt-get -yq install pwgen
fi

APP_DB_HOST=mysql
DB_PASSWORD=kahNgooj1eed4siech
CREATED_AT=${1}
APP_DB_NAME=${2}
APP_DB_USER=${3:-${APP_DB_NAME}}
APP_DB_PASSWORD=${4:-$(pwgen 20 1)}

if [ a${APP_DB_NAME} == "a" ]; then
  echo "ERROR: Empty APP_DB_NAME, please specify a database name. Usage: $0 db_name"
  exit 1
fi

echo "Creating database ${APP_DB_NAME} with user ${APP_DB_USER}  ..."
mysql -h ${APP_DB_HOST} -u root -p${DB_PASSWORD} -e 'CREATE DATABASE IF NOT EXISTS `'${APP_DB_NAME}'`; GRANT ALL PRIVILEGES ON `'${APP_DB_NAME}'`.* TO '\'${APP_DB_USER}\''@'\''%'\'' IDENTIFIED BY '\'${APP_DB_PASSWORD}\''; FLUSH PRIVILEGES;'
echo "Database ${APP_DB_NAME} successfully created"

