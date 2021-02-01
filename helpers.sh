install_tooling() {
    scripts=( \
                "amboss_bitcoind" "bitcoin-cli.sh" "Command line for your Bitcoin instance" \
                "amboss_clightning_bitcoin" "bitcoin-lightning-cli.sh" "Command line for your Bitcoin C-Lightning instance" \
                "amboss_lnd_bitcoin" "bitcoin-lncli.sh" "Command line for your Bitcoin LND instance" \
                "*" "amboss-down.sh" "Command line for stopping all services related to Amboss" \
                "*" "amboss-restart.sh" "Command line for restarting all services related to Amboss" \
                "*" "amboss-setup.sh" "Command line for restarting all services related to Amboss" \
                "*" "amboss-up.sh" "Command line for starting all services related to Amboss" \
                "*" "amboss-update.sh" "Command line for updating your Amboss to the latest commit of this repository" \
                "*" "changedomain.sh" "Command line for changing the external domain of your Amboss" \
            )

    i=0
    while [ $i -lt ${#scripts[@]} ]; do
        scriptname="${scripts[$i+1]}"
        dependency="${scripts[$i+0]}"
        comment="${scripts[$i+2]}"

        [ -e /usr/local/bin/$scriptname ] && rm /usr/local/bin/$scriptname
        if [ -e "$scriptname" ]; then
            if [ "$dependency" == "*" ] || ( [ -e "$AMBOSS_DOCKER_COMPOSE" ] && grep -q "$dependency" "$AMBOSS_DOCKER_COMPOSE" ); then
                chmod +x $scriptname
                ln -s "$(pwd)/$scriptname" /usr/local/bin
                echo "Installed $scriptname to /usr/local/bin: $comment"
            fi
        else
            echo "WARNING: Script $scriptname referenced, but not existing"
        fi
        i=`expr $i + 3`
    done
}

amboss_expand_variables() {
    AMBOSS_ANNOUNCEABLE_HOST=""
    if [[ "$AMBOSS_HOST" != *.local ]] && [[ "$AMBOSS_HOST" != *.lan ]]; then
        AMBOSS_ANNOUNCEABLE_HOST="$AMBOSS_HOST"
    fi
}

# Set .env file
amboss_update_docker_env() {
amboss_expand_variables
touch $AMBOSS_ENV_FILE

echo "
AMBOSS_PROTOCOL=$AMBOSS_PROTOCOL
AMBOSS_HOST=$AMBOSS_HOST
AMBOSS_ANNOUNCEABLE_HOST=$AMBOSS_ANNOUNCEABLE_HOST
REVERSEPROXY_HTTP_PORT=$REVERSEPROXY_HTTP_PORT
REVERSEPROXY_HTTPS_PORT=$REVERSEPROXY_HTTPS_PORT
REVERSEPROXY_DEFAULT_HOST=$REVERSEPROXY_DEFAULT_HOST
AMBOSS_IMAGE=$AMBOSS_IMAGE
ACME_CA_URI=$ACME_CA_URI
NBITCOIN_NETWORK=$NBITCOIN_NETWORK
LETSENCRYPT_EMAIL=$LETSENCRYPT_EMAIL
LIGHTNING_ALIAS=$LIGHTNING_ALIAS
AMBOSS_SSHTRUSTEDFINGERPRINTS=$AMBOSS_SSHTRUSTEDFINGERPRINTS
AMBOSS_SSHKEYFILE=$AMBOSS_SSHKEYFILE
AMBOSS_SSHAUTHORIZEDKEYS=$AMBOSS_SSHAUTHORIZEDKEYS
AMBOSS_HOST_SSHAUTHORIZEDKEYS=$AMBOSS_HOST_SSHAUTHORIZEDKEYS
AMBOSS_CRYPTOS=$AMBOSS_CRYPTOS
EPS_XPUB=$EPS_XPUB" > $AMBOSS_ENV_FILE
}

amboss_up() {
    pushd . > /dev/null
    cd "$(dirname "$AMBOSS_ENV_FILE")"
    docker-compose -f $AMBOSS_DOCKER_COMPOSE up --remove-orphans -d -t "${COMPOSE_HTTP_TIMEOUT:-180}"
    # Depending on docker-compose, either the timeout does not work, or "compose -d and --timeout cannot be combined"
    if ! [ $? -eq 0 ]; then
        docker-compose -f $AMBOSS_DOCKER_COMPOSE up --remove-orphans -d
    fi
    popd > /dev/null
}

amboss_pull() {
    pushd . > /dev/null
    cd "$(dirname "$AMBOSS_ENV_FILE")"
    docker-compose -f "$AMBOSS_DOCKER_COMPOSE" pull
    popd > /dev/null
}

amboss_down() {
    pushd . > /dev/null
    cd "$(dirname "$AMBOSS_ENV_FILE")"
    docker-compose -f $AMBOSS_DOCKER_COMPOSE down -t "${COMPOSE_HTTP_TIMEOUT:-180}"
    # Depending on docker-compose, the timeout does not work.
    if ! [ $? -eq 0 ]; then
        docker-compose -f $AMBOSS_DOCKER_COMPOSE down
    fi
    popd > /dev/null
}

amboss_restart() {
    pushd . > /dev/null
    cd "$(dirname "$AMBOSS_ENV_FILE")"
    docker-compose -f $AMBOSS_DOCKER_COMPOSE restart -t "${COMPOSE_HTTP_TIMEOUT:-180}"
    # Depending on docker-compose, the timeout does not work.
    if ! [ $? -eq 0 ]; then
        docker-compose -f $AMBOSS_DOCKER_COMPOSE restart
    fi
    popd > /dev/null
}