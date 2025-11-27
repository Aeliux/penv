if [ "$PENV_ENV_MODE" != "prepare" ]; then
    return 0
fi

# SSH host keys
if command -v ssh-keygen >/dev/null 2>&1; then
  ssh-keygen -A >/dev/null 2>&1 || true
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