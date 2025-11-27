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
MIRROR="${MIRROR:-}"

ADDITIONAL_PACKAGES="ca-certificates,file,curl,wget,gpg,less,iproute2,procps,iputils-ping,nano,ed,xz-utils,bzip2,zip,unzip,${ADDITIONAL_PACKAGES:-}"

# Distro configuration map
case "$DISTRO" in
    debian)
        DISTRO_RELEASE="${DISTRO_RELEASE:-trixie}"
        DEFAULT_MIRRORS=(
            "http://deb.debian.org/debian"
            "http://ftp.us.debian.org/debian"
        )
        KEYRING_PACKAGE="debian-archive-keyring"
        KEYRING_FILE="/usr/share/keyrings/debian-archive-keyring.gpg"
        DEBOOTSTRAP_OPTS="--arch=$DISTRO_ARCH --variant=minbase"
        ;;
    ubuntu)
        DISTRO_RELEASE="${DISTRO_RELEASE:-noble}"
        DEFAULT_MIRRORS=(
            "http://archive.ubuntu.com/ubuntu"
            "http://ports.ubuntu.com"
        )
        KEYRING_PACKAGE="ubuntu-keyring"
        KEYRING_FILE="/usr/share/keyrings/ubuntu-archive-keyring.gpg"
        DEBOOTSTRAP_OPTS="--arch=$DISTRO_ARCH --variant=minbase --components=main,universe"
        ;;
    *)
        echo "Error: Unsupported distro '$DISTRO'. Use 'debian' or 'ubuntu'." >&2
        exit 1
        ;;
esac

# Mirror selection (deduplicated)
if [ -n "$MIRROR" ]; then
    IFS=',' read -ra MIRRORS <<< "$MIRROR"
else
    MIRRORS=("${DEFAULT_MIRRORS[@]}")
fi

readonly ROOTFS_DIR="${ROOTFS_DIR:-/tmp/penv/$$/${DISTRO}-${DISTRO_RELEASE}-${DISTRO_ARCH}-rootfs}"

# Source build library
. build/core/build.sh

readonly PACKAGE_VERSION="${PENV_VERSION}"
readonly OUTPUT_FILE="${OUTPUT_FILE:-output/${DISTRO}-${DISTRO_RELEASE}-${DISTRO_ARCH}-${PACKAGE_VERSION}-rootfs.tar.gz}"

echo "Building ${DISTRO^} ${DISTRO_RELEASE} (${DISTRO_ARCH}) v$PACKAGE_VERSION rootfs..."

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

# Test mirrors for arch support
echo "Selecting mirror for $DISTRO_RELEASE ($DISTRO_ARCH)..."
select_mirror() {
    local release="$1"
    local arch="$2"
    shift 2
    local mirrors=("$@")
    for m in "${mirrors[@]}"; do
        url="$m/dists/$release/main/binary-$arch/Release"
        if wget -q --spider --timeout=10 "$url"; then
            echo "$m"
            return 0
        fi
    done
    return 1
}

set +e
MIRROR="$(select_mirror "$DISTRO_RELEASE" "$DISTRO_ARCH" "${MIRRORS[@]}")"
if [ -z "$MIRROR" ]; then
    echo "Error: No mirrors found for $DISTRO_RELEASE ($DISTRO_ARCH)" >&2
    exit 1
fi
set -e
echo "Using mirror: $MIRROR"

# Cleanup and prepare
if [ -d "$ROOTFS_DIR" ]; then
    # Check for mounted filesystems and FAIL IMMEDIATELY
    mountpoints_found=0
    for mp in dev dev/pts dev/shm proc sys; do
        if mountpoint -q "$ROOTFS_DIR/$mp"; then
            echo "Error: Mountpoint $ROOTFS_DIR/$mp is still mounted. Please unmount before proceeding." >&2
            mountpoints_found=1
        fi
    done
    if [ $mountpoints_found -ne 0 ]; then
        exit 1
    fi
    echo "Removing existing rootfs at $ROOTFS_DIR..."
    rm -rf "$ROOTFS_DIR"
fi
mkdir -p "$(dirname "$ROOTFS_DIR")"

# Detect foreign architecture and install binfmt if needed
HOST_ARCH="$(dpkg --print-architecture)"
foreign_arch=0
if [ "$HOST_ARCH" != "$DISTRO_ARCH" ]; then
    echo "Detected foreign architecture build: host=$HOST_ARCH, target=$DISTRO_ARCH"
    build::install_binfmt || { echo "Error: build::install_binfmt failed" >&2; exit 1; }
    foreign_arch=1
fi

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

# Update and upgrade packages inside chroot
echo "Updating and upgrading packages..."
build::chroot_script "build/debian/update-sources.sh" "$DISTRO" "$DISTRO_RELEASE" "$MIRROR" || { echo "Error: update-sources.sh failed" >&2; exit 1; }

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

