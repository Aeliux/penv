#!/bin/sh
set -e

# /penv/startup.sh
# This script sets up the runtime environment and launches a shell

if [ "$PENV_ENV_MODE" = "build" ]; then
    echo "Error: /penv/startup.sh should not be run in build mode" >&2
    exit 1
fi

# Cleanup function
cleanup() {
    # Source signal files
    if [ -d "$PENV_SIGNAL" ]; then
        for signal in "$PENV_SIGNAL"/*; do
            [ -r "$signal" ] || continue
            . "$signal"
        done
    fi

    # Run cleanup scripts in /penv/cleanup.d
    if [ -d /penv/cleanup.d ]; then
        for script in /penv/cleanup.d/*; do
            [ -x "$script" ] || continue
            "$script"
        done
    fi
}

trap cleanup EXIT INT TERM

export PENV_ENV_NAME=${PENV_ENV_NAME:-"unknown"}
export PENV_ENV_MODE=${PENV_ENV_MODE:-"unknown"}
export PENV_ENV_DISTRO="unknown"

export PENV_CONFIG_VERBOSE=${PENV_CONFIG_VERBOSE:-0}

# Unset all host environment variables except safe ones and PENV*
_SAFE_VARS="HOME USER SHELL TERM LANG LC_ALL LC_CTYPE PATH PWD OLDPWD SHLVL _"
for var in $(env | cut -d= -f1); do
    # Skip PENV* variables
    case "$var" in
        PENV_*) continue ;;
    esac
    # Skip safe variables
    _skip=0
    for safe in $_SAFE_VARS; do
        if [ "$var" = "$safe" ]; then
            _skip=1
            break
        fi
    done
    [ $_skip -eq 1 ] && continue
    # Unset the variable
    unset "$var"
done
unset _SAFE_VARS _skip var safe

# Set environment variables
export HOME="/root"
export USER="root"
export SHELL=${SHELL:-/bin/bash}
#export TERM=${TERM:-xterm-256color}
export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export SYSTEMD_OFFLINE=1

# Load metadata if available
if [ -f /penv/metadata.sh ]; then
    . /penv/metadata.sh
    export PENV_ENV_VERSION="$PENV_VERSION"
    export PENV_ENV_DISTRO="$PENV_METADATA_DISTRO"
    export PENV_ENV_FAMILY="$PENV_METADATA_FAMILY"
    export PENV_ENV_TIMESTAMP="$PENV_METADATA_TIMESTAMP"

    export PENV_VERSION
    export PENV_METADATA_DISTRO
    export PENV_METADATA_FAMILY
    export PENV_METADATA_TIMESTAMP
fi

# Ensure home directory exists
if [ ! -d "$HOME" ]; then
    mkdir -p "$HOME"
    chown root:root "$HOME"
    chmod 700 "$HOME"

    # Copy skel files if available
    if [ -d /etc/skel ]; then
        cp -a /etc/skel/. "$HOME"/
        chown -R root:root "$HOME"
        chmod -R go-rwx "$HOME"
    fi
fi

# Source all startup.d scripts
if [ -d /penv/startup.d ]; then
    for script in /penv/startup.d/*; do
        [ -r "$script" ] || continue
        . "$script"
    done
fi

# exit if mode is prepare
if [ "$PENV_ENV_MODE" = "prepare" ]; then
    exit 0
fi

# Set up penv signals
mkdir -p /temp/penv/signals
export PENV_SIGNAL="/temp/penv/signals"

# Launch shell
for shell in /bin/bash /usr/bin/bash /bin/sh /usr/bin/sh; do
    if [ -x "$shell" ]; then
        "$shell" --login
        exit $?
    fi
done

echo "Error: No shell found" >&2
exit 1
