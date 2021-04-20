#!/bin/bash

set +x

if [[ "$0" = "$BASH_SOURCE" ]]; then
    echo "This script must be sourced \". amboss-setup.sh\"" 
    exit 1
fi

if [[ "$OSTYPE" == "darwin"* ]]; then
    # Mac OS

    if [[ $EUID -eq 0 ]]; then
        # Running as root is discouraged on Mac OS. Run under the current user instead.
        echo "This script should not be run as root."
        return
    fi

    BASH_PROFILE_SCRIPT="$HOME/amboss-env.sh"

    # Mac OS doesn't use /etc/profile.d/xxx.sh. Instead we create a new file and load that from ~/.bash_profile
    if [[ ! -f "$HOME/.bash_profile" ]]; then
        touch "$HOME/.bash_profile"
    fi
    if [[ -z $(grep ". \"$BASH_PROFILE_SCRIPT\"" "$HOME/.bash_profile") ]]; then
        # Line does not exist, add it
        echo ". \"$BASH_PROFILE_SCRIPT\"" >> "$HOME/.bash_profile"
    fi

else
    # Root user is not needed for Mac OS
    BASH_PROFILE_SCRIPT="/etc/profile.d/amboss-env.sh"

    if [[ $EUID -ne 0 ]]; then
        echo "This script must be run as root after running \"sudo su -\""
        return
    fi
fi

# Verify we are in right folder. If we are not, let's go in the parent folder of the current docker-compose.
if ! git -C . rev-parse &> /dev/null || [ ! -d "Generated" ]; then
    if [[ ! -z $AMBOSS_DOCKER_COMPOSE ]]; then
        cd $(dirname $AMBOSS_DOCKER_COMPOSE)
        cd ..
    fi
    if ! git -C . rev-parse || [[ ! -d "Generated" ]]; then
        echo "You must run this script inside the git repository of amboss-docker"
        return
    fi
fi

function display_help () {
cat <<-END
Usage:
------

Install Amboss on this server
This script must be run as root, except on Mac OS

    -i : Run install and start Amboss
    --install-only: Run install only
    --docker-unavailable: Same as --install-only, but will also skip install steps requiring docker
    --no-startup-register: Do not register Amboss to start via systemctl or upstart
    --no-systemd-reload: Do not reload systemd configuration

This script will:

* Install Docker
* Install Docker-Compose
* Setup Amboss settings
* Make sure it starts at reboot via upstart or systemd
* Add Amboss utilities in /usr/bin
* Start Amboss

You can run again this script if you desire to change your configuration.

Make sure you own a domain with DNS record pointing to your website.
If you want HTTPS setup automatically with Let's Encrypt, leave REVERSEPROXY_HTTP_PORT at it's default value of 80 and make sure this port is accessible from the internet.
Or, if you want to offload SSL because you have an existing web proxy, change REVERSEPROXY_HTTP_PORT to any port you want. You can then forward the traffic. Just don't forget to pass the X-Forwarded-Proto header.

Environment variables:
    AMBOSS_HOST: The hostname of your website (eg. amboss.example.com)
    REVERSEPROXY_HTTP_PORT: The port the reverse proxy binds to for public HTTP requests. Default: 80
    REVERSEPROXY_HTTPS_PORT: The port the reverse proxy binds to for public HTTPS requests. Default: 443
    REVERSEPROXY_DEFAULT_HOST: Optional, if using a reverse proxy nginx, specify which website should be presented if the server is accessed by its IP.
    LETSENCRYPT_EMAIL: A mail will be sent to this address if certificate expires and fail to renew automatically (eg. me@example.com)
    AMBOSSGEN_REVERSEPROXY: Whether to use or not a reverse proxy. NGinx setup HTTPS for you. (eg. nginx, none. Default: nginx)
    AMBOSSGEN_ADDITIONAL_FRAGMENTS: Semi colon separated list of additional fragments you want to use (eg. opt-save-storage)
    ACME_CA_URI: The API endpoint to ask for HTTPS certificate (default: production)
    AMBOSS_ENABLE_SSH: Optional, gives Amboss SSH access to the host by allowing it to edit authorized_keys of the host, it can be used for managing the authorized_keys or updating Amboss directly through the website. (Default: false)
    AMBOSSGEN_DOCKER_IMAGE: Allows you to specify a custom docker image for the generator (Default: amboss/docker-compose-generator)
    AMBOSS_IMAGE: Allows you to specify the amboss docker image to use over the default version. (Default: current stable version of amboss)
    AMBOSS_PROTOCOL: Allows you to specify the external transport protocol of Amboss. (Default: https)
Add-on specific variables:
    AMBOSSGEN_EXCLUDE_FRAGMENTS:  Semicolon-separated list of fragments you want to forcefully exclude
END
}
START=""
HAS_DOCKER=true
STARTUP_REGISTER=true
SYSTEMD_RELOAD=true
while (( "$#" )); do
  case "$1" in
    -i)
      START=true
      shift 1
      ;;
    --install-only)
      START=false
      shift 1
      ;;
    --docker-unavailable)
      START=false
      HAS_DOCKER=false
      shift 1
      ;;
    --no-startup-register)
      STARTUP_REGISTER=false
      shift 1
      ;;
    --no-systemd-reload)
      SYSTEMD_RELOAD=false
      shift 1
      ;;
    --) # end argument parsing
      shift
      break
      ;;
    -*|--*=) # unsupported flags
      echo "Error: Unsupported flag $1" >&2
      display_help
      return
      ;;
    *) # preserve positional arguments
      PARAMS="$PARAMS $1"
      shift
      ;;
  esac
done

# If start does not have a value, stop here
if ! [[ "$START" ]]; then
    display_help
    return
fi

[[ $LETSENCRYPT_EMAIL == *@example.com ]] && echo "LETSENCRYPT_EMAIL ends with @example.com, setting to empty email instead" && LETSENCRYPT_EMAIL=""

: "${LETSENCRYPT_EMAIL:=}"
: "${AMBOSSGEN_REVERSEPROXY:=nginx}"
: "${REVERSEPROXY_DEFAULT_HOST:=none}"
: "${ACME_CA_URI:=production}"
: "${AMBOSS_PROTOCOL:=https}"
: "${REVERSEPROXY_HTTP_PORT:=80}"
: "${REVERSEPROXY_HTTPS_PORT:=443}"
: "${AMBOSS_ENABLE_SSH:=false}"

OLD_AMBOSS_DOCKER_COMPOSE="$AMBOSS_DOCKER_COMPOSE"
ORIGINAL_DIRECTORY="$(pwd)"
AMBOSS_BASE_DIRECTORY="$(dirname "$(pwd)")"
AMBOSS_DOCKER_COMPOSE="$(pwd)/Generated/docker-compose.generated.yml"

AMBOSS_ENV_FILE="$AMBOSS_BASE_DIRECTORY/.env"

AMBOSS_SSHKEYFILE=""
AMBOSS_SSHTRUSTEDFINGERPRINTS=""
use_ssh=false

if $AMBOSS_ENABLE_SSH && ! [[ "$AMBOSS_HOST_SSHAUTHORIZEDKEYS" ]]; then
    AMBOSS_HOST_SSHAUTHORIZEDKEYS=~/.ssh/authorized_keys
    AMBOSS_HOST_SSHKEYFILE=""
fi

if [[ -f "$AMBOSS_HOST_SSHKEYFILE" ]]; then
    echo -e "\033[33mWARNING: AMBOSS_HOST_SSHKEYFILE is now deprecated, use instead AMBOSS_ENABLE_SSH=true and run again '. amboss-setup.sh -i'\033[0m"
    AMBOSS_SSHKEYFILE="/datadir/id_rsa"
    use_ssh=true
fi

if $AMBOSS_ENABLE_SSH && [[ "$AMBOSS_HOST_SSHAUTHORIZEDKEYS" ]]; then
    if ! [[ -f "$AMBOSS_HOST_SSHAUTHORIZEDKEYS" ]]; then
        mkdir -p "$(dirname $AMBOSS_HOST_SSHAUTHORIZEDKEYS)"
        touch $AMBOSS_HOST_SSHAUTHORIZEDKEYS
    fi
    AMBOSS_SSHAUTHORIZEDKEYS="/datadir/host_authorized_keys"
    AMBOSS_SSHKEYFILE="/datadir/host_id_rsa"
    use_ssh=true
fi

# Do not set AMBOSS_SSHTRUSTEDFINGERPRINTS in the setup, since we connect from inside the docker container to the host, this is fine
AMBOSS_SSHTRUSTEDFINGERPRINTS=""

if [[ "$AMBOSSGEN_REVERSEPROXY" == "nginx" ]] && [[ "$AMBOSS_HOST" ]]; then
    DOMAIN_NAME="$(echo "$AMBOSS_HOST" | grep -E '^([a-z0-9]+(-[a-z0-9]+)*\.)+[a-z]{2,}$')"
    if [[ ! "$DOMAIN_NAME" ]]; then
        echo "AMBOSSGEN_REVERSEPROXY is set to nginx, so AMBOSS_HOST must be a domain name which point to this server, but the current value of AMBOSS_HOST ('$AMBOSS_HOST') is not a valid domain name."
        return
    fi
    AMBOSS_HOST="$DOMAIN_NAME"
fi

# Since opt-txindex requires unpruned node, throw an error if both
# opt-txindex and opt-save-storage-* are enabled together
if [[ "${AMBOSSGEN_ADDITIONAL_FRAGMENTS}" == *opt-txindex* ]] && \
   [[ "${AMBOSSGEN_ADDITIONAL_FRAGMENTS}" == *opt-save-storage* ]];then
        echo "Error: AMBOSSGEN_ADDITIONAL_FRAGMENTS contains both opt-txindex and opt-save-storage*"
        echo "opt-txindex requires an unpruned node, so you cannot use opt-save-storage with it"
        return
fi

cd "$AMBOSS_BASE_DIRECTORY/amboss-docker"
. helpers.sh
amboss_expand_variables

cd "$ORIGINAL_DIRECTORY"

echo "
-------SETUP-----------
Parameters passed:
AMBOSS_PROTOCOL:$AMBOSS_PROTOCOL
AMBOSS_HOST:$AMBOSS_HOST
REVERSEPROXY_HTTP_PORT:$REVERSEPROXY_HTTP_PORT
REVERSEPROXY_HTTPS_PORT:$REVERSEPROXY_HTTPS_PORT
REVERSEPROXY_DEFAULT_HOST:$REVERSEPROXY_DEFAULT_HOST
AMBOSS_ENABLE_SSH:$AMBOSS_ENABLE_SSH
AMBOSS_HOST_SSHKEYFILE:$AMBOSS_HOST_SSHKEYFILE
LETSENCRYPT_EMAIL:$LETSENCRYPT_EMAIL
AMBOSSGEN_REVERSEPROXY:$AMBOSSGEN_REVERSEPROXY
AMBOSSGEN_ADDITIONAL_FRAGMENTS:$AMBOSSGEN_ADDITIONAL_FRAGMENTS
AMBOSSGEN_EXCLUDE_FRAGMENTS:$AMBOSSGEN_EXCLUDE_FRAGMENTS
AMBOSS_IMAGE:$AMBOSS_IMAGE
ACME_CA_URI:$ACME_CA_URI
----------------------
Additional exported variables:
AMBOSS_DOCKER_COMPOSE=$AMBOSS_DOCKER_COMPOSE
AMBOSS_BASE_DIRECTORY=$AMBOSS_BASE_DIRECTORY
AMBOSS_ENV_FILE=$AMBOSS_ENV_FILE
AMBOSS_SSHKEYFILE=$AMBOSS_SSHKEYFILE
AMBOSS_SSHAUTHORIZEDKEYS=$AMBOSS_SSHAUTHORIZEDKEYS
AMBOSS_HOST_SSHAUTHORIZEDKEYS:$AMBOSS_HOST_SSHAUTHORIZEDKEYS
AMBOSS_SSHTRUSTEDFINGERPRINTS:$AMBOSS_SSHTRUSTEDFINGERPRINTS
AMBOSS_CRYPTOS:$AMBOSS_CRYPTOS
AMBOSS_ANNOUNCEABLE_HOST:$AMBOSS_ANNOUNCEABLE_HOST
----------------------
"

# Init the variables when a user log interactively
touch "$BASH_PROFILE_SCRIPT"
echo "
#!/bin/bash
export COMPOSE_HTTP_TIMEOUT=\"180\"
export AMBOSSGEN_REVERSEPROXY=\"$AMBOSSGEN_REVERSEPROXY\"
export AMBOSSGEN_ADDITIONAL_FRAGMENTS=\"$AMBOSSGEN_ADDITIONAL_FRAGMENTS\"
export AMBOSSGEN_EXCLUDE_FRAGMENTS=\"$AMBOSSGEN_EXCLUDE_FRAGMENTS\"
export AMBOSS_DOCKER_COMPOSE=\"$AMBOSS_DOCKER_COMPOSE\"
export AMBOSS_BASE_DIRECTORY=\"$AMBOSS_BASE_DIRECTORY\"
export AMBOSS_ENV_FILE=\"$AMBOSS_ENV_FILE\"
export AMBOSS_HOST_SSHKEYFILE=\"$AMBOSS_HOST_SSHKEYFILE\"
export AMBOSS_ENABLE_SSH=$AMBOSS_ENABLE_SSH
if cat \"\$AMBOSS_ENV_FILE\" &> /dev/null; then
  while IFS= read -r line; do
    ! [[ \"\$line\" == \"#\"* ]] && [[ \"\$line\" == *\"=\"* ]] && export \"\$line\"
  done < \"\$AMBOSS_ENV_FILE\"
fi
" > ${BASH_PROFILE_SCRIPT}

chmod +x ${BASH_PROFILE_SCRIPT}

echo -e "Amboss environment variables successfully saved in $BASH_PROFILE_SCRIPT\n"


amboss_update_docker_env

echo -e "Amboss docker-compose parameters saved in $AMBOSS_ENV_FILE\n"

. "$BASH_PROFILE_SCRIPT"

if ! [[ -x "$(command -v docker)" ]] || ! [[ -x "$(command -v docker-compose)" ]]; then
    if ! [[ -x "$(command -v curl)" ]]; then
        apt-get update 2>error
        apt-get install -y \
            curl \
            apt-transport-https \
            ca-certificates \
            software-properties-common \
            2>error
    fi
    if ! [[ -x "$(command -v docker)" ]]; then
        if [[ "$(uname -m)" == "x86_64" ]] || [[ "$(uname -m)" == "armv7l" ]] || [[ "$(uname -m)" == "aarch64" ]]; then
            if [[ "$OSTYPE" == "darwin"* ]]; then
                # Mac OS	
                if ! [[ -x "$(command -v brew)" ]]; then
                    # Brew is not installed, install it now
                    echo "Homebrew, the package manager for Mac OS, is not installed. Installing it now..."
                    /usr/bin/ruby -e "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/master/install)"
                fi
                if [[ -x "$(command -v brew)" ]]; then
                    echo "Homebrew is installed, but Docker isn't. Installing it now using brew..."
                    # Brew is installed, install docker now
                    # This sequence is a bit strange, but it's what what needed to get it working on a fresh Mac OS X Mojave install
                    brew cask install docker
                    brew install docker
                    brew link docker
                fi
            else
                # Not Mac OS
                echo "Trying to install docker..."
                curl -fsSL https://get.docker.com -o get-docker.sh
                chmod +x get-docker.sh
                sh get-docker.sh
                rm get-docker.sh
            fi
        else
            echo "Unsupported architecture $(uname -m)"
            return
        fi
    fi

    if ! [[ -x "$(command -v docker-compose)" ]]; then
        if ! [[ "$OSTYPE" == "darwin"* ]] && $HAS_DOCKER; then
            echo "Trying to install docker-compose by using the docker-compose-builder ($(uname -m))"
            ! [[ -d "dist" ]] && mkdir dist
            docker run --rm -v "$(pwd)/dist:/dist" btcpayserver/docker-compose-builder:1.24.1
            mv dist/docker-compose /usr/local/bin/docker-compose
            chmod +x /usr/local/bin/docker-compose
            rm -rf "dist"
        fi
    fi
fi

if $HAS_DOCKER; then
    if ! [[ -x "$(command -v docker)" ]]; then
        echo "Failed to install 'docker'. Please install docker manually, then retry."
        return
    fi

    if ! [[ -x "$(command -v docker-compose)" ]]; then
        echo "Failed to install 'docker-compose'. Please install docker-compose manually, then retry."
        return
    fi
fi

# Generate the docker compose in AMBOSS_DOCKER_COMPOSE
if $HAS_DOCKER; then
    if ! ./build.sh; then
        echo "Failed to generate the docker-compose"
        return
    fi
fi

# Schedule for reboot
if $STARTUP_REGISTER && [[ -x "$(command -v systemctl)" ]]; then
    # Use systemd
    if [[ -e "/etc/init/start_containers.conf" ]]; then
        echo -e "Uninstalling upstart script /etc/init/start_containers.conf"
        rm "/etc/init/start_containers.conf"
        initctl reload-configuration
    fi
    echo "Adding amboss.service to systemd"
    echo "
[Unit]
Description=Amboss service
After=docker.service network-online.target
Requires=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes

ExecStart=/bin/bash -c  '. \"$BASH_PROFILE_SCRIPT\" && cd \"\$AMBOSS_BASE_DIRECTORY/amboss-docker\" && . helpers.sh && amboss_up'
ExecStop=/bin/bash -c   '. \"$BASH_PROFILE_SCRIPT\" && cd \"\$AMBOSS_BASE_DIRECTORY/amboss-docker\" && . helpers.sh && amboss_down'
ExecReload=/bin/bash -c '. \"$BASH_PROFILE_SCRIPT\" && cd \"\$AMBOSS_BASE_DIRECTORY/amboss-docker\" && . helpers.sh && amboss_restart'

[Install]
WantedBy=multi-user.target" > /etc/systemd/system/amboss.service

    if ! [[ -f "/etc/docker/daemon.json" ]] && [ -w "/etc/docker" ]; then
        echo "{
\"log-driver\": \"json-file\",
\"log-opts\": {\"max-size\": \"5m\", \"max-file\": \"3\"}
}" > /etc/docker/daemon.json
        echo "Setting limited log files in /etc/docker/daemon.json"
        $SYSTEMD_RELOAD && $START && systemctl restart docker
    fi

    echo -e "Amboss systemd configured in /etc/systemd/system/amboss.service\n"
    if $SYSTEMD_RELOAD; then
        systemctl daemon-reload
        systemctl enable amboss
        if $START; then
            echo "Amboss starting... this can take 5 to 10 minutes..."
            systemctl start amboss
            echo "Amboss started"
        fi
    else
        systemctl --no-reload enable amboss
    fi
elif $STARTUP_REGISTER && [[ -x "$(command -v initctl)" ]]; then
    # Use upstart
    echo "Using upstart"
    echo "
# File is saved under /etc/init/start_containers.conf
# After file is modified, update config with : $ initctl reload-configuration

description     \"Start containers (see http://askubuntu.com/a/22105 and http://askubuntu.com/questions/612928/how-to-run-docker-compose-at-bootup)\"

start on filesystem and started docker
stop on runlevel [!2345]

# if you want it to automatically restart if it crashes, leave the next line in
# respawn # might cause over charge

script
    . \"$BASH_PROFILE_SCRIPT\"
    cd \"\$AMBOSS_BASE_DIRECTORY/amboss-docker\"
    . helpers.sh
    amboss_up
end script" > /etc/init/start_containers.conf
    echo -e "Amboss upstart configured in /etc/init/start_containers.conf\n"

    if $START; then
        initctl reload-configuration
    fi
fi


cd "$(dirname $AMBOSS_ENV_FILE)"

if $HAS_DOCKER && [[ ! -z "$OLD_AMBOSS_DOCKER_COMPOSE" ]] && [[ "$OLD_AMBOSS_DOCKER_COMPOSE" != "$AMBOSS_DOCKER_COMPOSE" ]]; then
    echo "Closing old docker-compose at $OLD_AMBOSS_DOCKER_COMPOSE..."
    docker-compose -f "$OLD_AMBOSS_DOCKER_COMPOSE" down -t "${COMPOSE_HTTP_TIMEOUT:-180}"
fi

if $START; then
    amboss_up
elif $HAS_DOCKER; then
    amboss_pull
fi

# Give SSH key to BTCPay
if $START && [[ -f "$AMBOSS_HOST_SSHKEYFILE" ]]; then
    echo -e "\033[33mWARNING: AMBOSS_HOST_SSHKEYFILE is now deprecated, use instead AMBOSS_ENABLE_SSH=true and run again '. amboss-setup.sh -i'\033[0m"
    echo "Copying $AMBOSS_SSHKEYFILE to BTCPayServer container"
    docker cp "$AMBOSS_HOST_SSHKEYFILE" $(docker ps --filter "name=_btcpayserver_" -q):$AMBOSS_SSHKEYFILE
fi

cd "$AMBOSS_BASE_DIRECTORY/amboss-docker"
install_tooling

cd $ORIGINAL_DIRECTORY
