#!/bin/bash -e

[ "$DEBUG" == "1" ] && set -x && set +e

if [ a"${DB_PASSWORD}" == "a" ]; then
  echo "=> ERROR: Missing DB_PASSWORD environment variable, use docker run -e DB_PASSWORD=XXXX ..."
  exit 1
fi

if [ a"${DB_HOST}" == "a" ]; then
  echo "=> ERROR: Missing DB_HOST environment variable, use docker run -e DB_HOST=XXXX ..."
  exit 1
fi

function cleanup {
  echo "=======>>>>> SOMETHING WAS WRONG - CLEANING UP <<<<<<======="
  echo "=> Deleting directory ${WP_INSTALL_DIR} ..."
  rm -rf ${WP_INSTALL_DIR}/*
  rm -f ${WP_INSTALL_DIR}/${WP_INSTALL_RUNNING_FLAG}
  exit 1
}

function install_wordpress {
  TIME_START=`date +%s`

  chown -R ${USER} ${WP_INSTALL_DIR}
  echo "=> Downloading wordpress version ${WP_VERSION} - this may take a while ..."
  timeout ${WP_CLI_TIMEOUT} sudo -E -u ${USER} -s -- wp core download --path=${WP_INSTALL_DIR} --version=${WP_VERSION}

  set +e
  while ! mysql --connect-timeout=5 -sB -h ${DB_HOST} -u ${DB_USER} -p${DB_PASSWORD} -e "SELECT 1 FROM DUAL" >/dev/null 2>&1; do
    echo "=> MySQL seems down, retrying ..."
    sleep 1
  done
  set -e

  echo "=> Creating wp-config.php file ..."
  timeout ${WP_CLI_TIMEOUT} sudo -E -u ${USER} -s -- wp config create --path=${WP_INSTALL_DIR} --dbname=${DB_NAME} --dbuser=${DB_USER} --dbpass=${DB_PASSWORD} --dbhost=${DB_HOST} --dbprefix=${DB_PREFIX} --dbcharset=${DB_CHARSET} --dbcollate=${DB_COLLATE} --extra-php --locale=${WP_LOCALE}
  chmod 660 ${WP_INSTALL_DIR}/wp-config.php

  echo "=> Creating Wordpress Database ..."
  timeout ${WP_CLI_TIMEOUT} sudo -E -u ${USER} -s -- wp core install --path=${WP_INSTALL_DIR} --url=${WP_SITEURL} --title="${WP_TITLE}" --admin_user=${WP_ADMIN_USER} --admin_password=${WP_ADMIN_PASSWORD} --admin_email=${WP_ADMIN_EMAIL}

  echo "=> Installing Wordpress language ${WP_LOCALE} ..."
  timeout ${WP_CLI_TIMEOUT} sudo -E -u ${USER} -s -- wp core language install ${WP_LOCALE} --activate --path=${WP_INSTALL_DIR}

  rm -f ${WP_INSTALL_DIR}/${WP_INSTALL_RUNNING_FLAG}
  chown -R ${USER} ${WP_INSTALL_DIR}

  TIME_END=`date +%s`
  echo "=> DONE, Wordpress installed in $((TIME_END-TIME_START)) seconds ..."
}

if [ ! -e ${WP_INSTALL_DIR}/${WP_INSTALL_RUNNING_FLAG} -a ! -e ${WP_INSTALL_DIR}/${WP_INSTALL_COMPLETED_FLAG} ]; then
  echo "=> Wordpress is not installed, running installation process ..."
  touch ${WP_INSTALL_DIR}/${WP_INSTALL_RUNNING_FLAG}
  trap "cleanup" EXIT
  install_wordpress
  trap - EXIT
else
  while ! mysql --connect-timeout=5 -sB -h ${DB_HOST} -u ${DB_USER} -p${DB_PASSWORD} -e "DESCRIBE ${DB_NAME}.${DB_PREFIX}options" >/dev/null 2>&1; do
    echo "=> Wordpress installation in process, waiting for it to be completed ..."
    sleep 1
  done
fi

exit 0
