#!/bin/sh
set -e

# Create necessary directories
mkdir -p /tmp /var/tmp /run /var/run /var/lock
chmod 1777 /tmp /var/tmp

# Create /run/shm symlink
ln -sf /dev/shm /run/shm 2>/dev/null || true

# Set up DNS with reliable nameservers
cat > /etc/resolv.conf <<EOF
nameserver 8.8.8.8
nameserver 8.8.4.4
nameserver 1.1.1.1
EOF

# Set default hostname
echo "penv" > /etc/hostname

# Set up hosts file
cat > /etc/hosts <<EOF
127.0.0.1   localhost penv
::1         localhost ip6-localhost ip6-loopback
ff02::1     ip6-allnodes
ff02::2     ip6-allrouters
EOF

# Set timezone to UTC
echo "UTC" > /etc/timezone
rm -f /etc/localtime
ln -s /usr/share/zoneinfo/UTC /etc/localtime 2>/dev/null || true

# Clear machine-id (will be regenerated if needed)
: > /etc/machine-id
mkdir -p /var/lib/dbus
: > /var/lib/dbus/machine-id 2>/dev/null || true

# Set default locale
cat > /etc/default/locale <<EOF
LANG=C.UTF-8
LC_ALL=C.UTF-8
EOF

# Set up passwd and group if they don't exist or are broken
if [ ! -s /etc/passwd ]; then
    cat > /etc/passwd <<EOF
root:x:0:0:root:/root:/bin/bash
nobody:x:65534:65534:nobody:/nonexistent:/usr/sbin/nologin
EOF
fi

if [ ! -s /etc/group ]; then
    cat > /etc/group <<EOF
root:x:0:
nogroup:x:65534:
EOF
fi

if [ ! -s /etc/shadow ]; then
    cat > /etc/shadow <<EOF
root:*:19000:0:99999:7:::
nobody:*:19000:0:99999:7:::
EOF
    chmod 640 /etc/shadow
fi

# Set up basic shell environment
if [ ! -f /etc/profile ]; then
    cat > /etc/profile <<EOF
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
export HOME=/root
export TERM=xterm-256color
EOF
fi

# Create mtab symlink if it doesn't exist
if [ ! -e /etc/mtab ]; then
    ln -sf /proc/mounts /etc/mtab
fi

# Fix systemd detection issues
mkdir -p /run/systemd 2>/dev/null || true
