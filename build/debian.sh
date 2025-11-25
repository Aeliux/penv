#!/usr/bin/env bash

set -euo pipefail

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root"
    exit 1
fi

cd "$(dirname "$0")/.."

# Configuration
FAMILY="debian"
DISTRO="${DISTRO:-debian}"  # debian or ubuntu
DISTRO_RELEASE="${DISTRO_RELEASE:-}"
DISTRO_ARCH="${DISTRO_ARCH:-amd64}"
ROOTFS_DIR="${ROOTFS_DIR:-/tmp/penv/${DISTRO}-rootfs}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
MIRROR="${MIRROR:-}"

# Set distro-specific defaults
case "$DISTRO" in
    debian)
        DISTRO_RELEASE="${DISTRO_RELEASE:-bookworm}"
        MIRROR="${MIRROR:-http://deb.debian.org/debian}"
        ;;
    ubuntu)
        DISTRO_RELEASE="${DISTRO_RELEASE:-noble}"
        MIRROR="${MIRROR:-http://archive.ubuntu.com/ubuntu}"
        ;;
    *)
        echo "Error: Unsupported distro '$DISTRO'. Use 'debian' or 'ubuntu'."
        exit 1
        ;;
esac

# Set output file if not specified
if [ -z "$OUTPUT_FILE" ]; then
    OUTPUT_FILE="output/${DISTRO}-${DISTRO_RELEASE}-${DISTRO_ARCH}-rootfs.tar.gz"
fi

. build/core/build.sh

echo "Building ${DISTRO^} ${DISTRO_RELEASE} (${DISTRO_ARCH}) rootfs..."

# Check if debootstrap is installed
if ! command -v debootstrap >/dev/null 2>&1; then
    echo "Error: debootstrap is not installed"
    exit 1
fi

# Install archive keyring if missing
case "$DISTRO" in
    debian)
        if [ ! -f /usr/share/keyrings/debian-archive-keyring.gpg ]; then
            echo "Installing debian-archive-keyring..."
            apt-get update
            apt-get install -y debian-archive-keyring
        fi
        ;;
    ubuntu)
        if [ ! -f /usr/share/keyrings/ubuntu-archive-keyring.gpg ]; then
            echo "Installing ubuntu-keyring..."
            apt-get update
            apt-get install -y ubuntu-keyring
        fi
        ;;
esac

# Test network connectivity
echo "Testing network connectivity..."
if ! wget -q --spider --timeout=10 "$MIRROR/dists/$DISTRO_RELEASE/Release" 2>/dev/null; then
    echo "Error: Cannot reach $MIRROR"
    echo "Trying alternative mirror..."
    case "$DISTRO" in
        debian)
            MIRROR="http://ftp.us.debian.org/debian"
            ;;
        ubuntu)
            MIRROR="http://us.archive.ubuntu.com/ubuntu"
            ;;
    esac
    if ! wget -q --spider --timeout=10 "$MIRROR/dists/$DISTRO_RELEASE/Release" 2>/dev/null; then
        echo "Error: Cannot reach any ${DISTRO^} mirrors. Check your network connection and DNS."
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
mkdir -p "$(dirname "$ROOTFS_DIR")" || exit 1

# Create rootfs using debootstrap
echo "Running debootstrap..."
if [ "$DISTRO" = "ubuntu" ]; then
    # Ubuntu requires additional components
    debootstrap --arch="$DISTRO_ARCH" --variant=minbase --components=main,universe --verbose "$DISTRO_RELEASE" "$ROOTFS_DIR" "$MIRROR" || exit 1
else
    debootstrap --arch="$DISTRO_ARCH" --variant=minbase --verbose "$DISTRO_RELEASE" "$ROOTFS_DIR" "$MIRROR" || exit 1
fi

# Setup penv in rootfs
if ! build::setup; then
    echo "Error: build::setup failed" >&2
    exit 1
fi

if ! build::finalize; then
    echo "Error: build::finalize failed" >&2
    exit 1
fi

# Ensure output directory exists
mkdir -p "$(dirname "$OUTPUT_FILE")"
chmod 755 "$(dirname "$OUTPUT_FILE")"

# Create tar.gz archive
echo "Creating tar.gz archive..."
rm -f "$OUTPUT_FILE"
tar -czf "$OUTPUT_FILE" -C "$ROOTFS_DIR" .
chmod 644 "$OUTPUT_FILE"

# Clean up rootfs directory
echo "Removing temporary rootfs directory..."
rm -rf "$ROOTFS_DIR"

echo "Done! rootfs saved to: $OUTPUT_FILE"
echo "Size: $(du -h "$OUTPUT_FILE" | cut -f1)"

