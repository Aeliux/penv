#!/bin/sh
set -e

# /penv/startup.sh
# This script sets up the runtime environment and launches a shell

# Cleanup function
cleanup() {
    rm -f /tmp/.proot-* 2>/dev/null || true
}

trap cleanup EXIT INT TERM

# Set environment variables
export HOME=${HOME:-/root}
export USER=${USER:-root}
export SHELL=${SHELL:-/bin/bash}
export TERM=${TERM:-xterm-256color}
export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$PATH"
export SYSTEMD_OFFLINE=1

# Ensure home directory exists
mkdir -p "$HOME" 2>/dev/null || true

# Source all startup.d scripts
if [ -d /penv/startup.d ]; then
    for script in /penv/startup.d/*; do
        [ -r "$script" ] || continue
        . "$script"
    done
fi

# Launch shell
for shell in /bin/bash /usr/bin/bash /bin/sh /usr/bin/sh; do
    if [ -x "$shell" ]; then
        exec "$shell" -l
    fi
done

echo "Error: No shell found" >&2
exit 1
