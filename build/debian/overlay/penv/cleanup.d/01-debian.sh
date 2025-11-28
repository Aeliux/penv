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

# Remove apt cache
rm $RM_FLAGS /var/cache/apt || true

if [ "$PENV_ENV_MODE" != "build" ] && [ "$PENV_ENV_MODE" != "mod" ] && [ -z "$PENV_SIGNAL_CLEANUP" ]; then
    exit 0
fi

if [ $VERBOSE -eq 1 ]; then
    echo "Cleaning Debian-specific files..."
fi

# Remove apt lists
rm $RM_FLAGS /var/lib/apt/lists/* || true

# remove apt logs
for log in /var/log/apt/history.log /var/log/apt/term.log; do
    [ -f "$log" ] && { [ $VERBOSE -eq 1 ] && echo "trunc: $log"; : > "$log"; }
done

exit 0