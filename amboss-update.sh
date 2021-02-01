#!/bin/bash

set -e

if [[ "$OSTYPE" == "darwin"* ]]; then
	# Mac OS
	BASH_PROFILE_SCRIPT="$HOME/amboss-env.sh"

else
	# Linux
	BASH_PROFILE_SCRIPT="/etc/profile.d/amboss-env.sh"
fi

. ${BASH_PROFILE_SCRIPT}

cd "$AMBOSS_BASE_DIRECTORY/amboss-docker"

if [[ "$1" != "--skip-git-pull" ]]; then
    git pull --force
    exec "amboss-update.sh" --skip-git-pull
    return
fi

if ! [ -f "/etc/docker/daemon.json" ] && [ -w "/etc/docker" ]; then
    echo "{
\"log-driver\": \"json-file\",
\"log-opts\": {\"max-size\": \"5m\", \"max-file\": \"3\"}
}" > /etc/docker/daemon.json
    echo "Setting limited log files in /etc/docker/daemon.json"
fi

if ! ./build.sh; then
    echo "Failed to generate the docker-compose"
    exit 1
fi

if ! grep -Fxq "export COMPOSE_HTTP_TIMEOUT=\"180\"" "$BASH_PROFILE_SCRIPT"; then
    echo "export COMPOSE_HTTP_TIMEOUT=\"180\"" >> "$BASH_PROFILE_SCRIPT"
    export COMPOSE_HTTP_TIMEOUT=180
    echo "Adding COMPOSE_HTTP_TIMEOUT=180 in amboss-env.sh"
fi

if [[ "$ACME_CA_URI" == "https://acme-v01.api.letsencrypt.org/directory" ]]; then
    original_acme="$ACME_CA_URI"
    export ACME_CA_URI="production"
    echo "Info: Rewriting ACME_CA_URI from $original_acme to $ACME_CA_URI"
fi

if [[ "$ACME_CA_URI" == "https://acme-staging.api.letsencrypt.org/directory" ]]; then
    original_acme="$ACME_CA_URI"
    export ACME_CA_URI="staging"
    echo "Info: Rewriting ACME_CA_URI from $original_acme to $ACME_CA_URI"
fi

. helpers.sh
install_tooling
amboss_update_docker_env
amboss_up

set +e
docker image prune -af --filter "label!=amboss.image=docker-compose-generator"
