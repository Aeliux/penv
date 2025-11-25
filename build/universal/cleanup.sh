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

# tmp and var tmp
del /tmp/* || true
del /var/tmp/* || true

# user caches and histories
del /root/.cache || true
for d in /home/*/.cache; do del "$d" || true; done
for h in /root/.bash_history /root/.ash_history /root/.zsh_history; do trunc "$h" || true; done
for u in /home/*; do for hh in "$u"/.*history; do trunc "$hh" || true; done; done

# logs: truncate files, remove archived logs and journal
for f in /var/log/*; do if [[ -f "$f" ]]; then trunc "$f"; fi; done
del /var/log/*.gz || true
del /var/log/*.[0-9] || true
del /var/log/journal || true

# runtime caches and thumbnails
del /var/cache/fontconfig || true
find / -type d -name "__pycache__" -prune -exec bash -c 'if [[ $0 == "" ]]; then exit 0; fi; rm -rf "$0" >/dev/null 2>&1' {} \; 2>/dev/null || true
del /root/.cache/pip || true
del /var/cache/pip || true
del /root/.npm || true
del /root/.cache/yarn || true

# thumbnails and user UI caches
del /root/.thumbnails || true
for d in /home/*/.thumbnails; do del "$d" || true; done

# remove snap/flatpak caches if present
del /var/lib/snapd || true
del /var/cache/flatpak || true

# leftover caches and temporary package data
del /var/cache/man || true
del /var/cache/* || true

# remove docs and manpages
del /usr/share/doc || true
del /usr/share/man || true
del /usr/share/info || true
del /usr/share/locale || true
del /usr/local/share/doc || true
del /usr/local/share/man || true
del /usr/local/share/info || true
del /usr/local/share/locale || true

# Remove all logs
find / -type f -name "*.log" -delete 2>/dev/null || true

# libtool leftovers
find / -type f -name "*.la" -delete 2>/dev/null || true

exit 0