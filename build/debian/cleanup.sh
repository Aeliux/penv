#!/usr/bin/env bash
set -e

if [ "$PENV_ENV_MODE" != "build" ] && [ "$PENV_ENV_MODE" != "mod" ]; then
    exit 0
fi

VERBOSE=0
if [[ "${1:-}" == "-v" ]]; then VERBOSE=1; fi
log(){ [[ $VERBOSE -eq 1 ]] && echo "$*"; }
del(){ if [[ $VERBOSE -eq 1 ]]; then echo "[DEL] $1"; rm -rf -- "$1"; else rm -rf -- "$1" >/dev/null 2>&1; fi }
trunc(){ if [[ -f "$1" ]]; then if [[ $VERBOSE -eq 1 ]]; then echo "[TRUNC] $1"; : > "$1"; else : > "$1"; fi; fi }

# Remove apt lists and cached debs
del /var/lib/apt/lists/* || true
del /var/cache/apt || true

# remove apt/logs
trunc /var/log/apt/history.log || true
trunc /var/log/apt/term.log || true

exit 0