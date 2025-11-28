#!/bin/sh

set -e

VERBOSE=${PENV_CONFIG_VERBOSE:-0}
[ "${1:-}" = "-v" ] && VERBOSE=1

# Set command flags based on verbosity
if [ $VERBOSE -eq 1 ]; then
    RM_FLAGS="-rfv"
else
    RM_FLAGS="-rf"
fi

# Remove pacman package cache
rm $RM_FLAGS /var/cache/pacman/pkg/* || true

if [ "$PENV_ENV_MODE" != "build" ] && [ "$PENV_ENV_MODE" != "mod" ] && [ -z "$PENV_SIGNAL_CLEANUP" ]; then
    exit 0
fi

if [ $VERBOSE -eq 1 ]; then
    echo "Cleaning Arch-specific files..."
fi

# Clean pacman cache
pacman -Sccq --noconfirm || true

# Remove pacman sync database
rm $RM_FLAGS /var/lib/pacman/sync/* || true

# Remove pacman logs
: > /var/log/pacman.log || true

# Remove pacman lock file
rm $RM_FLAGS /var/lib/pacman/db.lck || true

exit 0