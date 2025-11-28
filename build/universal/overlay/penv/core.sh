# Set default PENV variables
export PENV_ENV_NAME=${PENV_ENV_NAME:-unknown}
export PENV_ENV_MODE=${PENV_ENV_MODE:-unknown}
export PENV_ENV_DISTRO=${PENV_ENV_DISTRO:-unknown}
export PENV_BUILD_STAGE=${PENV_BUILD_STAGE:-unknown}
export PENV_CONFIG_VERBOSE=${PENV_CONFIG_VERBOSE:-0}

# Set up runtime signal directory
export PENV_SIGNAL=${PENV_SIGNAL:-"/tmp/penv/signals"}
rm -rf "$PENV_SIGNAL"
mkdir -p "$PENV_SIGNAL"

# Load metadata if core not already loaded
if [ -z "$PENV_CORE_LOADED" ]; then
    if [ -f /penv/metadata.sh ]; then
        . /penv/metadata.sh
        
        export PENV_VERSION
        export PENV_METADATA_FAMILY
        export PENV_METADATA_DISTRO
        export PENV_METADATA_TIMESTAMP
        
        export PENV_ENV_VERSION="$PENV_VERSION"
        export PENV_ENV_DISTRO="$PENV_METADATA_DISTRO"
        export PENV_ENV_FAMILY="$PENV_METADATA_FAMILY"
        export PENV_ENV_TIMESTAMP="$PENV_METADATA_TIMESTAMP"
    else
        echo "Error: Corrupted environment: missing /penv/metadata.sh" >&2
        exit 1
    fi
fi

# Set standard environment
export HOME="/root"
export USER="root"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

export SYSTEMD_OFFLINE=1
export SYSTEMD_LOG_LEVEL=err

export PENV_CORE_LOADED=1