#!/bin/sh
set -e

VERBOSE=${PENV_CONFIG_VERBOSE:-0}
if [ "${1:-}" = "-v" ]; then VERBOSE=1; fi

# Set rm flags based on verbosity
if [ $VERBOSE -eq 1 ]; then
    RM_FLAGS="-rfv"
else
    RM_FLAGS="-rf"
fi

if [ $VERBOSE -eq 1 ]; then
    echo "Performing basic cleanup..."
fi

# tmp and var tmp
rm $RM_FLAGS /tmp/* || true
rm $RM_FLAGS /var/tmp/* || true

exit 0