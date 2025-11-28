# 01-machine-id.sh - idempotent machine-id creation without dbus
# Creates /etc/machine-id (32 hex chars + newline) if it does not exist or is empty.
# Also copies to /var/lib/dbus/machine-id for compatibility.

if [ "$PENV_ENV_MODE" != "prepare" ]; then
    return 0
fi

MFILE=/etc/machine-id
DBUSFILE=/var/lib/dbus/machine-id

# do nothing if a non-empty machine-id already exists
if [ -s "$MFILE" ]; then
  return 0
fi

# generate 32 hex chars (lowercase) using best available source
generate_from_procuuid() {
  if [ -r /proc/sys/kernel/random/uuid ]; then
    # convert UUID with dashes to 32 hex chars
    tr -d '-' < /proc/sys/kernel/random/uuid | tr 'A-Z' 'a-z'
    return 0
  fi
  return 1
}

generate_from_uuidgen() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr -d '-' | tr 'A-Z' 'a-z'
    return 0
  fi
  return 1
}

generate_from_openssl() {
  if command -v openssl >/dev/null 2>&1; then
    # 16 bytes -> 32 hex chars
    openssl rand -hex 16
    return 0
  fi
  return 1
}

generate_from_dd() {
  # fallback: read 16 bytes from /dev/urandom and print hex (busybox may not have xxd)
  if command -v od >/dev/null 2>&1; then
    # od exists on most minimal images
    od -An -v -t x1 -N 16 /dev/urandom | tr -d ' \n' | tr 'A-Z' 'a-z'
    return 0
  fi
  return 1
}

# try generators in order
id=""
id=$(generate_from_procuuid 2>/dev/null || true)
[ -z "$id" ] && id=$(generate_from_uuidgen 2>/dev/null || true)
[ -z "$id" ] && id=$(generate_from_openssl 2>/dev/null || true)
[ -z "$id" ] && id=$(generate_from_dd 2>/dev/null || true)

if [ -z "$id" ]; then
  # as an absolute fallback, use date+pid+random hashed (very unlikely)
  rand=$(awk 'BEGIN{srand(); printf "%08x%08x\n", int(rand()*0xffffffff), int(rand()*0xffffffff)}')
  id=$(printf '%s' "$rand" | cut -c1-32)
fi

# ensure we got 32 hex chars; otherwise abort without writing
case "$id" in
  [0-9a-f][0-9a-f]*)
    # ensure length 32
    id=$(printf '%s' "$id" | sed 's/[^0-9a-f]//g' | cut -c1-32)
    if [ "$(printf '%s' "$id" | wc -c)" -ne 32 ]; then
      printf 'Machine-id generation failed (invalid length)\n' >&2
      return 1
    fi
    ;;
  *)
    printf 'Machine-id generation failed (invalid chars)\n' >&2
    return 1
    ;;
esac

# write atomically
tmp="$(mktemp /tmp/machine-id.XXXXXX)"
printf '%s\n' "$id" > "$tmp"
# ensure dir exists
mkdir -p "$(dirname "$MFILE")"
mv "$tmp" "$MFILE"
chmod 0644 "$MFILE" || true

# for compatibility with legacy dbus users
mkdir -p "$(dirname "$DBUSFILE")"
# Skip if the file links to /etc/machine-id
if [ -L "$DBUSFILE" ] && [ "$(readlink -f "$DBUSFILE")" = "$MFILE" ]; then
    return 0
else
    # remove existing file if any
    rm -f "$DBUSFILE"
fi

ln -s "$MFILE" "$DBUSFILE"
