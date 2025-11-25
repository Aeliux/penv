#!/bin/sh
set -e

VERBOSE=${PENV_CONFIG_VERBOSE:-0}
if [ "${1:-}" = "-v" ]; then VERBOSE=1; fi
log(){ [ $VERBOSE -eq 1 ] && echo "$*"; }
del(){ if [ $VERBOSE -eq 1 ]; then echo "[DEL] $1"; rm -rf -- "$1"; else rm -rf -- "$1" >/dev/null 2>&1; fi }
trunc(){ if [ -f "$1" ]; then if [ $VERBOSE -eq 1 ]; then echo "[TRUNC] $1"; : > "$1"; else : > "$1"; fi; fi }

# tmp and var tmp
del /tmp/* || true
del /var/tmp/* || true

exit 0