#!/bin/sh

set -e

if [ "$PENV_ENV_MODE" != "build" ] && [ "$PENV_ENV_MODE" != "mod" ] && [ -z "$PENV_SIGNAL_CLEANUP" ]; then
    exit 0
fi

VERBOSE=${PENV_CONFIG_VERBOSE:-0}
[ "${1:-}" = "-v" ] && VERBOSE=1

if ! command -v file >/dev/null 2>&1; then
    [ $VERBOSE -eq 1 ] && echo "file command not found, skipping stripping step."
    exit 0
fi

if ! command -v strip >/dev/null 2>&1; then
    [ $VERBOSE -eq 1 ] && echo "strip command not found, skipping stripping step."
    exit 0
fi

# Strip unneeded symbols from binaries to reduce size
[ $VERBOSE -eq 1 ] && echo "Stripping unneeded symbols from binaries..."
find / -type f -exec sh -c '
    file="$1"
    mime=$(file -b --mime-type "$file")
    if [ "${mime#application/}" = elf ]; then
        [ $VERBOSE -eq 1 ] && echo "Stripping $file"
        strip --strip-unneeded "$file"
    fi
' sh {} \;

exit 0