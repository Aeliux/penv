#!/usr/bin/env bash

set -euo pipefail

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

# Configuration
readonly FAMILY="debian"
readonly DISTRO="${DISTRO:-debian}"  # debian or ubuntu
DISTRO_RELEASE="${DISTRO_RELEASE:-}"
readonly DISTRO_ARCH="${DISTRO_ARCH:-amd64}"
readonly ROOTFS_DIR="${ROOTFS_DIR:-/tmp/penv/${DISTRO}-rootfs}"
OUTPUT_FILE="${OUTPUT_FILE:-}"
MIRROR="${MIRROR:-}"

ADDITIONAL_PACKAGES="ca-certificates,file,curl,wget,gpg,less,iproute2,procps,iputils-ping,nano,vim,xz-utils,bzip2,zip,unzip,${ADDITIONAL_PACKAGES:-}"

# Distro configuration map
case "$DISTRO" in
    debian)
        DISTRO_RELEASE="${DISTRO_RELEASE:-bookworm}"
        MIRROR="${MIRROR:-http://deb.debian.org/debian}"
        KEYRING_PACKAGE="debian-archive-keyring"
        KEYRING_FILE="/usr/share/keyrings/debian-archive-keyring.gpg"
        FALLBACK_MIRROR="http://ftp.us.debian.org/debian"
        DEBOOTSTRAP_OPTS="--arch=$DISTRO_ARCH --variant=minbase"
        ;;
    ubuntu)
        DISTRO_RELEASE="${DISTRO_RELEASE:-noble}"
        MIRROR="${MIRROR:-http://archive.ubuntu.com/ubuntu}"
        KEYRING_PACKAGE="ubuntu-keyring"
        KEYRING_FILE="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
        FALLBACK_MIRROR="http://us.archive.ubuntu.com/ubuntu"
        DEBOOTSTRAP_OPTS="--arch=$DISTRO_ARCH --variant=minbase --components=main,universe"
        ;;
    *)
        echo "Error: Unsupported distro '$DISTRO'. Use 'debian' or 'ubuntu'." >&2
        exit 1
        ;;
esac

OUTPUT_FILE="${OUTPUT_FILE:-output/${DISTRO}-${DISTRO_RELEASE}-${DISTRO_ARCH}-rootfs.tar.gz}"

# Source build functions
. build/core/build.sh

echo "Building ${DISTRO^} ${DISTRO_RELEASE} (${DISTRO_ARCH}) rootfs..."

# Verify dependencies
if ! command -v debootstrap >/dev/null 2>&1; then
    echo "Error: debootstrap is not installed" >&2
    exit 1
fi

# Ensure keyring is installed
if [ ! -f "$KEYRING_FILE" ]; then
    echo "Installing $KEYRING_PACKAGE..."
    apt-get update -qq
    apt-get install -y "$KEYRING_PACKAGE"
fi

# Test mirror connectivity
echo "Testing network connectivity..."
if ! wget -q --spider --timeout=10 "$MIRROR/dists/$DISTRO_RELEASE/Release" 2>/dev/null; then
    echo "Warning: Primary mirror unreachable, trying fallback..." >&2
    MIRROR="$FALLBACK_MIRROR"
    if ! wget -q --spider --timeout=10 "$MIRROR/dists/$DISTRO_RELEASE/Release" 2>/dev/null; then
        echo "Error: Cannot reach any ${DISTRO^} mirrors. Check network/DNS." >&2
        exit 1
    fi
fi
echo "Using mirror: $MIRROR"

# Clean up and prepare
[ -d "$ROOTFS_DIR" ] && rm -rf "$ROOTFS_DIR"
mkdir -p "$(dirname "$ROOTFS_DIR")"

# Bootstrap rootfs
echo "Running debootstrap..."
cache_dir="/var/cache/penv/$DISTRO/$DISTRO_RELEASE"
mkdir -p "$cache_dir"
debootstrap $DEBOOTSTRAP_OPTS \
    --include="$ADDITIONAL_PACKAGES" \
    --cache-dir="$cache_dir" \
    --verbose "$DISTRO_RELEASE" \
    "$ROOTFS_DIR" \
    "$MIRROR"

# Setup and finalize
build::setup || { echo "Error: build::setup failed" >&2; exit 1; }
build::finalize || { echo "Error: build::finalize failed" >&2; exit 1; }

# Create archive
echo "Creating tar.gz archive..."
mkdir -p "$(dirname "$OUTPUT_FILE")"
tar -czf "$OUTPUT_FILE" -C "$ROOTFS_DIR" .
chmod 644 "$OUTPUT_FILE"

# Cleanup
rm -rf "$ROOTFS_DIR"

echo "Done! rootfs saved to: $OUTPUT_FILE"
echo "Size: $(du -h "$OUTPUT_FILE" | cut -f1)"

