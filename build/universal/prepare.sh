if [ "$PENV_ENV_MODE" != "prepare" ]; then
    return 0
fi

VERBOSE=0
if [ "${1:-}" = "-v" ]; then VERBOSE=1; fi
log(){ [ $VERBOSE -eq 1 ] && echo "$*"; }

# SSH host keys (if ssh-keygen exists)
if command -v ssh-keygen >/dev/null 2>&1; then
  if [ $VERBOSE -eq 1 ]; then echo "[RUN] ssh-keygen -A"; ssh-keygen -A; else ssh-keygen -A >/dev/null 2>&1 || true; fi
fi

# machine-id: prefer systemd helper, fall back to dbus-uuidgen or python
if command -v systemd-machine-id-setup >/dev/null 2>&1; then
  if [ $VERBOSE -eq 1 ]; then echo "[RUN] systemd-machine-id-setup"; systemd-machine-id-setup || true; else systemd-machine-id-setup >/dev/null 2>&1 || true; fi
elif command -v dbus-uuidgen >/dev/null 2>&1; then
  if [ $VERBOSE -eq 1 ]; then echo "[RUN] dbus-uuidgen > /etc/machine-id"; dbus-uuidgen > /etc/machine-id || true; else dbus-uuidgen > /etc/machine-id 2>/dev/null || true; fi
elif command -v python3 >/dev/null 2>&1; then
  if [ $VERBOSE -eq 1 ]; then echo "[RUN] python3 generate machine-id"; python3 - <<'PY' > /etc/machine-id
import uuid,sys
sys.stdout.write(str(uuid.uuid4()))
PY
  else python3 - <<'PY' > /etc/machine-id
import uuid,sys
sys.stdout.write(str(uuid.uuid4()))
PY
  fi
fi

# ldconfig (if present)
if command -v ldconfig >/dev/null 2>&1; then
  if [ $VERBOSE -eq 1 ]; then echo "[RUN] ldconfig"; ldconfig || true; else ldconfig >/dev/null 2>&1 || true; fi
fi

# update CA certs (if present)
if command -v update-ca-certificates >/dev/null 2>&1; then
  if [ $VERBOSE -eq 1 ]; then echo "[RUN] update-ca-certificates"; update-ca-certificates || true; else update-ca-certificates >/dev/null 2>&1 || true; fi
fi

# locales: if /etc/locale.gen and locale-gen exist
if [ -f /etc/locale.gen ] && command -v locale-gen >/dev/null 2>&1; then
  if [ $VERBOSE -eq 1 ]; then echo "[RUN] locale-gen"; locale-gen || true; else locale-gen >/dev/null 2>&1 || true; fi
fi

exit 0