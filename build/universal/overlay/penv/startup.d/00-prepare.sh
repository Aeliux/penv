if [ "$PENV_ENV_MODE" != "prepare" ]; then
    return 0
fi

# SSH host keys
if command -v ssh-keygen >/dev/null 2>&1; then
  ssh-keygen -A >/dev/null 2>&1 || true
fi

# machine-id: prefer systemd helper, fall back to dbus-uuidgen or python
if command -v systemd-machine-id-setup >/dev/null 2>&1; then
  systemd-machine-id-setup >/dev/null 2>&1 || true
elif command -v dbus-uuidgen >/dev/null 2>&1; then
  dbus-uuidgen > /etc/machine-id 2>/dev/null || true
elif command -v python3 >/dev/null 2>&1; then
  python3 - <<'PY' > /etc/machine-id
import uuid,sys
sys.stdout.write(str(uuid.uuid4()))
PY
fi

# ldconfig
if command -v ldconfig >/dev/null 2>&1; then
  ldconfig >/dev/null 2>&1 || true
fi

# update CA certs
if command -v update-ca-certificates >/dev/null 2>&1; then
  update-ca-certificates >/dev/null 2>&1 || true
fi

# locales
if [ -f /etc/locale.gen ] && command -v locale-gen >/dev/null 2>&1; then
  locale-gen >/dev/null 2>&1 || true
fi

exit 0