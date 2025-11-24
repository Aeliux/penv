#!/bin/sh
set -e

# /penv/startup.sh
# This script sets up the runtime environment and launches a shell

# Cleanup function
cleanup() {
    rm -rf /tmp/* 2>/dev/null || true
    rm -rf /var/tmp/* 2>/dev/null || true
    rm -rf /var/run/*.pid 2>/dev/null || true
    rm -rf /run/*.pid 2>/dev/null || true

    # Delete temp files generated during runtime
    if [ "$PENV_ENV_MODE" = "mod" ]; then
        rm -f "$HOME"/.bash_history 2>/dev/null || true
        rm -f "$HOME"/.zsh_history 2>/dev/null || true
        rm -f "$HOME"/.sudo_as_admin_successful 2>/dev/null || true
    fi

    # Run any additional cleanup scripts in /penv/cleanup.d
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
# Get penv metadata
if [ -f /penv/metadata/distro ]; then
    PENV_ENV_DISTRO=$(cat /penv/metadata/distro)
fi

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
export PATH="/usr/local/sbin:/usr/local/bin:/usr/games:/usr/sbin:/usr/bin:/sbin:/bin"
export SYSTEMD_OFFLINE=1

# Ensure home directory exists
mkdir -p "$HOME" 2>/dev/null || true

# Source all startup.d scripts (skip if mode is mod)
if [ "$PENV_ENV_MODE" != "mod" ] && [ -d /penv/startup.d ]; then
    for script in /penv/startup.d/*; do
        [ -r "$script" ] || continue
        . "$script"
    done
fi

# Launch shell
for shell in /bin/bash /usr/bin/bash /bin/sh /usr/bin/sh; do
    if [ -x "$shell" ]; then
        "$shell" --login
        exit $?
    fi
done

echo "Error: No shell found" >&2
exit 1
