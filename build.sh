#!/bin/bash

set -e

: "${AMBOSSGEN_DOCKER_IMAGE:=amboss/docker-compose-generator}"
if [ "$AMBOSSGEN_DOCKER_IMAGE" == "amboss/docker-compose-generator:local" ]
then
    docker build docker-compose-generator -f docker-compose-generator/linuxamd64.Dockerfile --tag $AMBOSSGEN_DOCKER_IMAGE
else
    set +e
    docker pull $AMBOSSGEN_DOCKER_IMAGE
    docker rmi $(docker images amboss/docker-compose-generator --format "{{.Tag}};{{.ID}}" | grep "^<none>" | cut -f2 -d ';') > /dev/null 2>&1
    set -e
fi

# This script will run docker-compose-generator in a container to generate the yml files
docker run -v "$(pwd)/Generated:/app/Generated" \
           -v "$(pwd)/docker-compose-generator/docker-fragments:/app/docker-fragments" \
           -e "AMBOSS_FULLNODE=$AMBOSS_FULLNODE" \
           -e "AMBOSSGEN_REVERSEPROXY=$AMBOSSGEN_REVERSEPROXY" \
           -e "AMBOSSGEN_ADDITIONAL_FRAGMENTS=$AMBOSSGEN_ADDITIONAL_FRAGMENTS" \
           -e "AMBOSSGEN_EXCLUDE_FRAGMENTS=$AMBOSSGEN_EXCLUDE_FRAGMENTS" \
           -e "AMBOSSGEN_LIGHTNING=$AMBOSSGEN_LIGHTNING" \
           -e "AMBOSSGEN_SUBNAME=$AMBOSSGEN_SUBNAME" \
           -e "AMBOSS_HOST_SSHAUTHORIZEDKEYS=$AMBOSS_HOST_SSHAUTHORIZEDKEYS" \
           -e "EPS_XPUB=$EPS_XPUB" \
           --rm $AMBOSSGEN_DOCKER_IMAGE

if [ "$AMBOSSGEN_REVERSEPROXY" == "nginx" ]; then
    cp Production/nginx.tmpl Generated/nginx.tmpl
fi

[[ -f "Generated/pull-images.sh" ]] && chmod +x Generated/pull-images.sh
[[ -f "Generated/save-images.sh" ]] && chmod +x Generated/save-images.sh

if [ "$AMBOSSGEN_REVERSEPROXY" == "traefik" ]; then
    cp Traefik/traefik.toml Generated/traefik.toml
    :> Generated/acme.json
    chmod 600 Generated/acme.json
fi
