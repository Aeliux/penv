#!/bin/sh
set -e

# Create necessary directories
mkdir -p /tmp /var/tmp /run /var/run /var/lock
chmod 1777 /tmp /var/tmp

# Create /run/shm symlink
ln -sf /dev/shm /run/shm 2>/dev/null || true

# Set up DNS if resolv.conf doesn't exist or is empty
if [ ! -s /etc/resolv.conf ]; then
    cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF
fi

# Set hostname if not set
if [ ! -f /etc/hostname ]; then
    echo "proot" > /etc/hostname
fi

# Basic hosts file
if [ ! -f /etc/hosts ]; then
    cat > /etc/hosts <<EOF
127.0.0.1   localhost
::1         localhost ip6-localhost ip6-loopback
EOF
fi

# Set timezone if not set
if [ ! -f /etc/timezone ]; then
    echo "UTC" > /etc/timezone
fi

# Fix systemd detection issues
mkdir -p /run/systemd 2>/dev/null || true
