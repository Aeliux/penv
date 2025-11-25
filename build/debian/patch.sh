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
Dir::Cache "";
Dir::Cache::archives "";
Binary::apt::APT::Keep-Downloaded-Packages "false";
APT::Keep-Downloaded-Packages "false";
EOF

# Prevent doc generation
mkdir -p /etc/dpkg/dpkg.cfg.d
cat > /etc/dpkg/dpkg.cfg.d/01_nodoc <<EOF
path-exclude=/usr/share/locale/*
path-exclude=/usr/share/man/*
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-exclude=/usr/share/doc/*
path-exclude=/usr/share/info/*
EOF
mkdir -p /etc/dpkg/dpkg.conf.d
cp /etc/dpkg/dpkg.cfg.d/01_nodoc /etc/dpkg/dpkg.conf.d/01_nodoc

# Disable unnecessary services
if [ -d /etc/systemd/system ]; then
    systemctl mask systemd-remount-fs.service 2>/dev/null || true
    systemctl mask systemd-logind.service 2>/dev/null || true
fi

# Clean up package manager cache
apt-get clean
rm -rf /var/lib/apt/lists/*
