#!/bin/bash

DOCKER_COMPOSE_VERSION=1.23.2
DOCKER_COMPOSE_FILE=https://github.com/unsimplesistemista/docker-wordpress/blob/master/docker-compose.yml
DOCKER_COMPOSE_FILE_TMP=/tmp/1ss-docker-compose.yml
DOCKER_COMPOSE_PROJECT=wordpress

if ! command -V docker >/dev/null; then
  echo "=> Installing docker ..."
  wget -qO- https://get.docker.com/ | sh
fi

if ! command -V docker-compose >/dev/null; then
  sudo curl -sSL "https://github.com/docker/compose/releases/download/${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
  sudo chmod +x /usr/local/bin/docker-compose
fi

curl -sSL ${DOCKER_COMPOSE_FILE} -o ${DOCKER_COMPOSE_FILE_TMP}
docker-compose -p ${DOCKER_COMPOSE_PROJECT} -f ${DOCKER_COMPOSE_FILE_TMP} up -d
exit 0
