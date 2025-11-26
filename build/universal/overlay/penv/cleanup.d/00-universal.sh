#!/bin/sh
set -e

if [ "$PENV_ENV_MODE" != "build" ] && [ "$PENV_ENV_MODE" != "mod" ] && [ -z "$PENV_SIGNAL_CLEANUP" ]; then
    exit 0
fi

VERBOSE=${PENV_CONFIG_VERBOSE:-0}
[ "${1:-}" = "-v" ] && VERBOSE=1

# Set command flags based on verbosity
if [ $VERBOSE -eq 1 ]; then
    # RM_FLAGS="-rfv"
    # FIND_DELETE_FLAGS="-print -delete"

    RM_FLAGS="-rf"
    FIND_DELETE_FLAGS="-delete"
else
    RM_FLAGS="-rf"
    FIND_DELETE_FLAGS="-delete"
fi

# Exclude system paths from find operations
FIND_EXCLUDES="-path /dev -prune -o -path /proc -prune -o -path /sys -prune -o -path /mnt -prune -o"

if [ $VERBOSE -eq 1 ]; then
    echo "Performing deep cleanup..."
fi

# tmp and var tmp
rm $RM_FLAGS /tmp/* || true
rm $RM_FLAGS /var/tmp/* || true

# user caches and histories
rm $RM_FLAGS /root/.cache || true
for d in /home/*/.cache; do [ -e "$d" ] && rm $RM_FLAGS "$d" || true; done

# truncate history files
for h in /root/.bash_history /root/.ash_history /root/.zsh_history; do
    if [ -f "$h" ]; then
        [ $VERBOSE -eq 1 ] && echo "trunc: $h"
        : > "$h"
    fi
done
for u in /home/*; do 
    for hh in "$u"/.*history; do
        if [ -f "$hh" ]; then
            [ $VERBOSE -eq 1 ] && echo "trunc: $hh"
            : > "$hh"
        fi
    done
done

# logs: truncate files, remove archived logs and journal
for f in /var/log/*; do
    if [ -f "$f" ]; then
        [ $VERBOSE -eq 1 ] && echo "trunc: $f"
        : > "$f"
    fi
done
rm $RM_FLAGS /var/log/*.gz || true
rm $RM_FLAGS /var/log/*.[0-9] || true
rm $RM_FLAGS /var/log/journal || true

# runtime caches and thumbnails
rm $RM_FLAGS /var/cache/fontconfig || true
find / $FIND_EXCLUDES -type d -name "__pycache__" -print0 | xargs -0 rm $RM_FLAGS || true
rm $RM_FLAGS /root/.cache/pip || true
rm $RM_FLAGS /var/cache/pip || true
rm $RM_FLAGS /root/.npm || true
rm $RM_FLAGS /root/.cache/yarn || true
# thumbnails and user UI caches
rm $RM_FLAGS /root/.thumbnails || true
for d in /home/*/.thumbnails; do [ -e "$d" ] && rm $RM_FLAGS "$d" || true; done

# remove snap/flatpak caches if present
rm $RM_FLAGS /var/lib/snapd || true
rm $RM_FLAGS /var/cache/flatpak || true

# leftover caches and temporary package data
rm $RM_FLAGS /var/cache/man || true
rm $RM_FLAGS /var/cache/* || true

# remove docs and manpages
rm $RM_FLAGS /usr/share/doc || true
rm $RM_FLAGS /usr/share/man || true
rm $RM_FLAGS /usr/share/info || true
rm $RM_FLAGS /usr/share/locale || true
rm $RM_FLAGS /usr/local/share/doc || true
rm $RM_FLAGS /usr/local/share/man || true
rm $RM_FLAGS /usr/local/share/info || true
rm $RM_FLAGS /usr/local/share/locale || true

# Remove all logs
find / $FIND_EXCLUDES -type f -name "*.log" -print0 | xargs -0 rm $RM_FLAGS || true

# libtool leftovers
find / $FIND_EXCLUDES -type f -name "*.la" -print0 | xargs -0 rm $RM_FLAGS || true

exit 0