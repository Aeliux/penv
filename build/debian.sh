#!/usr/bin/env bash

set -euo pipefail

cd "$(dirname "$0")/.."

# Configuration
DEBIAN_RELEASE="${DEBIAN_RELEASE:-bookworm}"
DEBIAN_ARCH="${DEBIAN_ARCH:-amd64}"
ROOTFS_DIR="${ROOTFS_DIR:-/tmp/penv/debian-rootfs}"
OUTPUT_FILE="${OUTPUT_FILE:-output/debian-${DEBIAN_RELEASE}-${DEBIAN_ARCH}-rootfs.tar.gz}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "Building Debian ${DEBIAN_RELEASE} (${DEBIAN_ARCH}) rootfs..."

# Check if debootstrap is installed
if ! command -v debootstrap >/dev/null 2>&1; then
    echo "Error: debootstrap is not installed"
    echo "Install it with: sudo apt-get install debootstrap"
    exit 1
fi

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

# Install debian-archive-keyring if missing
if [ ! -f /usr/share/keyrings/debian-archive-keyring.gpg ]; then
    echo "Installing debian-archive-keyring..."
    apt-get update
    apt-get install -y debian-archive-keyring
fi

# Test network connectivity
echo "Testing network connectivity..."
if ! wget -q --spider --timeout=10 "$MIRROR/dists/$DEBIAN_RELEASE/Release" 2>/dev/null; then
    echo "Error: Cannot reach $MIRROR"
    echo "Trying alternative mirror..."
    MIRROR="http://ftp.us.debian.org/debian"
    if ! wget -q --spider --timeout=10 "$MIRROR/dists/$DEBIAN_RELEASE/Release" 2>/dev/null; then
        echo "Error: Cannot reach any Debian mirrors. Check your network connection and DNS."
        exit 1
    fi
    echo "Using mirror: $MIRROR"
fi

# Clean up previous build
if [ -d "$ROOTFS_DIR" ]; then
    echo "Removing existing rootfs directory..."
    rm -rf "$ROOTFS_DIR"
fi

# Create parent directory if it doesn't exist
mkdir -p "$(dirname "$ROOTFS_DIR")"

# Create rootfs using debootstrap
echo "Running debootstrap..."
debootstrap --arch="$DEBIAN_ARCH" --variant=minbase --verbose "$DEBIAN_RELEASE" "$ROOTFS_DIR" "$MIRROR"

# Basic cleanup
echo "Cleaning up rootfs..."
rm -rf "$ROOTFS_DIR"/var/cache/apt/archives/*.deb
rm -rf "$ROOTFS_DIR"/var/lib/apt/lists/*
rm -rf "$ROOTFS_DIR"/tmp/*

# Apply penv patches
echo "Applying penv patches..."
if [ ! -f helpers/setup.sh ]; then
    echo "Error: helpers/setup.sh not found"
    exit 1
fi
helpers/setup.sh "$ROOTFS_DIR"

# Copy debian startup script
if [ ! -f helpers/deb-start.sh ]; then
    echo "Error: helpers/deb-start.sh not found"
    exit 1
fi
if [ ! -d "$ROOTFS_DIR/penv/startup.d" ]; then
    echo "Error: $ROOTFS_DIR/penv/startup.d directory was not created by setup.sh"
    exit 1
fi
cp helpers/deb-start.sh "$ROOTFS_DIR/penv/startup.d/debian.sh"
chmod +x "$ROOTFS_DIR/penv/startup.d/debian.sh"

# Apply Debian-specific patches
echo "Applying Debian patches..."
if [ -f helpers/patches/debian.sh ]; then
    mkdir -p "$ROOTFS_DIR/tmp"
    cp helpers/patches/debian.sh "$ROOTFS_DIR/tmp/debian.sh"
    chmod +x "$ROOTFS_DIR/tmp/debian.sh"
    chroot "$ROOTFS_DIR" /bin/sh /tmp/debian.sh
    rm -f "$ROOTFS_DIR/tmp/debian.sh"
fi

# Fix permissions
helpers/fix-perm.sh "$ROOTFS_DIR"

# Create tar.gz archive
echo "Creating tar.gz archive..."
tar -czf "$OUTPUT_FILE" -C "$ROOTFS_DIR" .

# Clean up rootfs directory
echo "Removing temporary rootfs directory..."
rm -rf "$ROOTFS_DIR"

echo "Done! Rootfs saved to: $OUTPUT_FILE"
echo "Size: $(du -h "$OUTPUT_FILE" | cut -f1)"

