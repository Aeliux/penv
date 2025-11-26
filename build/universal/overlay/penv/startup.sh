#!/bin/sh
set -e

# /penv/startup.sh
# This script sets up the runtime environment and launches a shell

# Cleanup function
cleanup() {
    # Source signal files
    if [ -d "$PENV_SIGNAL" ]; then
        for signal in "$PENV_SIGNAL"/*; do
            [ -r "$signal" ] && . "$signal"
        done
    fi

    if [ "$PENV_ENV_MODE" = "build" ] && [ "$PENV_BUILD_STAGE" != "cleanup" ] && [ "$PENV_BUILD_STAGE" != "test" ]; then
        return 0
    fi

    # Run cleanup scripts
    if [ -d /penv/cleanup.d ]; then
        for script in /penv/cleanup.d/*; do
            [ -x "$script" ] && "$script"
        done
    fi
}

trap cleanup EXIT INT TERM

# Set default PENV variables
export PENV_ENV_NAME=${PENV_ENV_NAME:-unknown}
export PENV_ENV_MODE=${PENV_ENV_MODE:-unknown}
export PENV_ENV_DISTRO=${PENV_ENV_DISTRO:-unknown}
export PENV_BUILD_STAGE=${PENV_BUILD_STAGE:-unknown}
export PENV_CONFIG_VERBOSE=${PENV_CONFIG_VERBOSE:-0}

# Set up runtime signal directory
export PENV_SIGNAL="/tmp/penv/signals/$$"
rm -rf "$PENV_SIGNAL"
mkdir -p "$PENV_SIGNAL"

# Load metadata
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
    echo Corrupted environment: missing /penv/metadata.sh >&2
    exit 1
fi

# Unset host environment variables (keep PENV_* and safe variables)
for var in $(env | cut -d= -f1); do
    case "$var" in
        PENV_*|HOME|USER|SHELL|TERM|LANG|LC_ALL|LC_CTYPE|PATH|PWD|OLDPWD|SHLVL|_)
            continue ;;
        *)
            unset "$var" ;;
    esac
done

# Set standard environment
export HOME="/root"
export USER="root"
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export SYSTEMD_OFFLINE=1

# Ensure home directory exists with proper structure
if [ ! -d "$HOME" ]; then
    mkdir -p "$HOME"
    [ -d /etc/skel ] && cp -a /etc/skel/. "$HOME"/
    chown -R root:root "$HOME"
    chmod 700 "$HOME"
fi

# Source startup scripts
if [ -d /penv/startup.d ]; then
    for script in /penv/startup.d/*; do
        [ -r "$script" ] && . "$script"
    done
fi

# Apply patches during build
if [ "$PENV_ENV_MODE" = "build" ] && [ "$PENV_BUILD_STAGE" = "patch" ] && [ -d /penv/patch.d ]; then
    [ "$PENV_CONFIG_VERBOSE" -ge 1 ] && echo "Applying patches in /penv/patch.d..."
    for script in /penv/patch.d/*; do
        if [ -x "$script" ]; then
            [ "$PENV_CONFIG_VERBOSE" -ge 1 ] && echo "Running patch script: $script"
            "$script"
        fi
    done
fi

if [ "$PENV_ENV_MODE" = "build" ] && [ "$PENV_BUILD_STAGE" = "test" ] && [ -x /penv/test.sh ]; then
    [ "$PENV_CONFIG_VERBOSE" -ge 1 ] && echo "Running tests"
    /penv/test.sh
fi

# Exit early for build modes
case "$PENV_ENV_MODE" in
    prepare|build)
        exit 0 ;;
esac

# Launch shell
for shell in /bin/bash /usr/bin/bash /bin/sh /usr/bin/sh; do
    if [ -x "$shell" ]; then
        export SHELL="$shell"
        "$shell" -l
        exit $?
    fi
done

echo "Error: No shell found" >&2
exit 1
