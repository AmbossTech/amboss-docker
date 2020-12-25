#!/bin/bash

. /etc/profile.d/amboss-env.sh

export NEW_HOST="$1"

if [[ "$NEW_HOST" == https:* ]] || [[ "$NEW_HOST" == http:* ]]; then
echo "The domain should not start by http: or https:"
else
export OLD_HOST=`cat $AMBOSS_ENV_FILE | sed -n 's/^AMBOSS_HOST=\(.*\)$/\1/p'`
echo "Changing domain from \"$OLD_HOST\" to \"$NEW_HOST\""

export AMBOSS_HOST="$NEW_HOST"
export ACME_CA_URI="production"
[[ "$OLD_HOST" == "$REVERSEPROXY_DEFAULT_HOST" ]] && export REVERSEPROXY_DEFAULT_HOST="$NEW_HOST"
pushd . > /dev/null
# Modify environment file
cd "$AMBOSS_BASE_DIRECTORY/amboss-docker"
. helpers.sh
amboss_update_docker_env
amboss_up
popd > /dev/null
fi