#!/bin/bash

if [[ "$OSTYPE" == "darwin"* ]]; then
	# Mac OS
	BASH_PROFILE_SCRIPT="$HOME/amboss-env.sh"

else
	# Linux
	BASH_PROFILE_SCRIPT="/etc/profile.d/amboss-env.sh"
fi

. ${BASH_PROFILE_SCRIPT}

cd "$AMBOSS_BASE_DIRECTORY/amboss-docker"
. helpers.sh
amboss_up
