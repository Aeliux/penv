#!/bin/sh
set -e

# /penv/startup.sh
# This script sets up the runtime environment and launches a shell or executes a command

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

# Unset host environment variables (keep PENV_* and safe variables)
for var in $(env | cut -d= -f1); do
    case "$var" in
        PENV_*|HOME|USER|SHELL|TERM|COLORTERM|LANG|LC_ALL|LC_CTYPE|DISPLAY|PATH|PWD|OLDPWD|SHLVL|_)
            continue ;;
        *)
            unset "$var" ;;
    esac
done

# Check for prepare signal
if [ "$PENV_ENV_MODE" = "environment" ] && [ -f /penv/.prepare_required ]; then
    export PENV_ENV_MODE="prepare"
    export PENV_PREPARE_REQUIRED=1
    echo "Preparation required, running preparation scripts..."
fi

# Load core environment
if [ -f /penv/core.sh ]; then
    . /penv/core.sh
else
    echo "Error: Corrupted environment: missing /penv/core.sh" >&2
    exit 1
fi

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
should_exit=0
case "$PENV_ENV_MODE" in
    prepare|build)
        if [ -n "$PENV_PREPARE_REQUIRED" ] && [ "$PENV_ENV_MODE" = "prepare" ]; then
            rm -f /penv/.prepare_required
            echo "Preparation steps completed. Please restart the environment."
        fi
        should_exit=1
        ;;
esac

# Launch shell or execute command
if [ "$#" -gt 0 ]; then
    "$@"
    exit $?
elif [ $should_exit -eq 1 ]; then
    exit 0
fi

for shell in /bin/bash /usr/bin/bash /bin/sh /usr/bin/sh; do
    if [ -x "$shell" ]; then
        export SHELL="$shell"
        "$shell" -l
        exit $?
    fi
done

echo "Error: No shell found" >&2
exit 1
