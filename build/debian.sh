#!/bin/sh

set -e

# Configuration
DEBIAN_RELEASE="${DEBIAN_RELEASE:-bookworm}"
DEBIAN_ARCH="${DEBIAN_ARCH:-amd64}"
ROOTFS_DIR="${ROOTFS_DIR:-./out/debian-rootfs}"
OUTPUT_FILE="${OUTPUT_FILE:-debian-${DEBIAN_RELEASE}-${DEBIAN_ARCH}-rootfs.tar.gz}"
MIRROR="${MIRROR:-http://deb.debian.org/debian}"

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

mkdir -p "$ROOTFS_DIR"

# Create rootfs using debootstrap
echo "Running debootstrap..."
debootstrap --arch="$DEBIAN_ARCH" --variant=minbase --verbose "$DEBIAN_RELEASE" "$ROOTFS_DIR" "$MIRROR"

# Basic cleanup
echo "Cleaning up rootfs..."
rm -rf "$ROOTFS_DIR"/var/cache/apt/archives/*.deb
rm -rf "$ROOTFS_DIR"/var/lib/apt/lists/*
rm -rf "$ROOTFS_DIR"/tmp/*

# Create tar.gz archive
echo "Creating tar.gz archive..."
tar -czf "$OUTPUT_FILE" -C "$ROOTFS_DIR" .

# Clean up rootfs directory
echo "Removing temporary rootfs directory..."
rm -rf "$ROOTFS_DIR"

echo "Done! Rootfs saved to: $OUTPUT_FILE"
echo "Size: $(du -h "$OUTPUT_FILE" | cut -f1)"

