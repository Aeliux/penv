#!/usr/bin/env bash

set -euo pipefail

# helpers/setup.sh
# This script applies necessary patches to the rootfs without chrooting into it.
# It should be run with the rootfs directory as the first argument.

# Set cwd to the script's directory
cd "$(dirname "$0")/.."

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <rootfs-directory>" >&2
    exit 1
fi

ROOTFS_DIR=$1
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Create penv dirs
mkdir -p "$ROOTFS_DIR"/penv
mkdir -p "$ROOTFS_DIR"/penv/metadata
mkdir -p "$ROOTFS_DIR"/penv/startup.d
mkdir -p "$ROOTFS_DIR"/penv/cleanup.d

# Write metadata in two formats
echo "1" > "$ROOTFS_DIR"/penv/metadata/version
echo "$FAMILY" > "$ROOTFS_DIR"/penv/metadata/family
echo "$DISTRO" > "$ROOTFS_DIR"/penv/metadata/distro
echo "$timestamp" > "$ROOTFS_DIR"/penv/metadata/timestamp

cat > "$ROOTFS_DIR"/penv/metadata.json <<EOF
{
  "version": 1,
  "family": "$FAMILY",
  "distro": "$DISTRO",
  "timestamp": "$timestamp"
}
EOF

# Apply overrides to rootfs recursively
echo "Applying overrides..."
cp -a overrides/. "$ROOTFS_DIR"/

# Set up root user
echo "Setting up root user..."
cp -a overrides/etc/skel/. "$ROOTFS_DIR"/root/

# Copy startup script
cp helpers/startup.sh "$ROOTFS_DIR"/penv/startup.sh
chmod +x "$ROOTFS_DIR"/penv/startup.sh

# Apply universal patches
echo "Applying universal patches..."
if [ -f helpers/patches/universal.sh ]; then
    mkdir -p "$ROOTFS_DIR/tmp"
    cp helpers/patches/universal.sh "$ROOTFS_DIR/tmp/universal.sh"
    chmod +x "$ROOTFS_DIR/tmp/universal.sh"
    chroot "$ROOTFS_DIR" /bin/sh /tmp/universal.sh
    rm -f "$ROOTFS_DIR/tmp/universal.sh"
fi
