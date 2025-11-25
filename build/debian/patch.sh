#!/bin/sh
set -e

# Generate C.UTF-8 locale
if command -v locale-gen >/dev/null 2>&1; then
    locale-gen C.UTF-8 2>/dev/null || true
fi

# Configure apt to work better in proot
mkdir -p /etc/apt/apt.conf.d
cat > /etc/apt/apt.conf.d/99proot <<EOF
APT::Sandbox::User "root";
Acquire::Retries "3";
Acquire::http::Timeout "10";
EOF

# Disable unnecessary services
if [ -d /etc/systemd/system ]; then
    systemctl mask systemd-remount-fs.service 2>/dev/null || true
    systemctl mask systemd-logind.service 2>/dev/null || true
fi

# Clean up package manager cache
apt-get clean
rm -rf /var/lib/apt/lists/*
