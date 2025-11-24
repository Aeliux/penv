#!/bin/sh
set -e

# /penv/startup.sh
# This script sets up the runtime environment and launches a shell

# Cleanup function
cleanup() {
    rm -f /tmp/.proot-* 2>/dev/null || true
}

trap cleanup EXIT INT TERM

export PENV_ENV_NAME=${PENV_ENV_NAME:-"unknown"}
export PENV_ENV_MODE=${PENV_ENV_MODE:-"unknown"}
export PENV_ENV_DISTRO="unknown"
# Get penv metadata
if [ -f /penv/metadata/distro ]; then
    PENV_ENV_DISTRO=$(cat /penv/metadata/distro)
fi

# Unset host environment variables that may interfere
unset LD_PRELOAD
unset LD_LIBRARY_PATH
unset PYTHONPATH
unset PERL5LIB
unset RUBYLIB
unset GEM_PATH
unset GOPATH
unset NODE_PATH
unset JAVA_HOME
unset CLASSPATH


# Set environment variables
export HOME="/root"
export USER="root"
export SHELL=${SHELL:-/bin/bash}
#export TERM=${TERM:-xterm-256color}
export LANG=${LANG:-C.UTF-8}
export LC_ALL=${LC_ALL:-C.UTF-8}
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export SYSTEMD_OFFLINE=1

# Ensure home directory exists
mkdir -p "$HOME" 2>/dev/null || true

# patch bashrc to support 256 colors (only once)
if [ -f "$HOME/.bashrc" ] && [ ! -f /penv/.bashrc_patched ]; then
    sed -i 's/xterm-color)/xterm-color|*-256color)/' "$HOME/.bashrc"
    
    # Add custom penv prompt
    cat >> "$HOME/.bashrc" << 'EOF'

# Custom penv prompt
if [ "$color_prompt" = yes ]; then
    PS1='(\[\033[01;36m\]${PENV_ENV_NAME}\[\033[00m\]@\[\033[01;35m\]${PENV_ENV_DISTRO}\[\033[00m\]) \[\033[01;34m\]\w\[\033[00m\]# '
else
    PS1='(${PENV_ENV_NAME}@${PENV_ENV_DISTRO}) \w# '
fi
EOF
    
    # Create marker file
    touch /penv/.bashrc_patched
fi

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
        exec "$shell" --login
    fi
done

echo "Error: No shell found" >&2
exit 1
