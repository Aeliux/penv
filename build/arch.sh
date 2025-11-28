#!/usr/bin/env bash

set -euo pipefail

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root" >&2
    exit 1
fi

cd "$(dirname "$0")/.."

# Configuration
readonly FAMILY="arch"
readonly DISTRO="arch"
readonly DISTRO_RELEASE="latest"
readonly DISTRO_ARCH="amd64"
readonly ROOTFS_DIR="${ROOTFS_DIR:-/tmp/penv/$$/${DISTRO}-${DISTRO_RELEASE}-${DISTRO_ARCH}-rootfs}"

# :)
readonly ARCH_ARCH="x86_64"

# Source build library
. build/core/build.sh

readonly PACKAGE_VERSION="${PENV_VERSION}"
readonly OUTPUT_FILE="${OUTPUT_FILE:-output/${DISTRO}-${DISTRO_RELEASE}-${DISTRO_ARCH}-${PACKAGE_VERSION}-rootfs.tar.gz}"

echo "Building ${DISTRO^} ${DISTRO_RELEASE} (${DISTRO_ARCH}) v$PACKAGE_VERSION rootfs..."

build::prepare_rootfs || { echo "Error: build::prepare_rootfs failed" >&2; exit 1; }

# Detect foreign architecture and install binfmt if needed
HOST_ARCH="$(dpkg --print-architecture)"
foreign_arch=0
if [ "$HOST_ARCH" != "$DISTRO_ARCH" ]; then
    echo "Detected foreign architecture build: host=$HOST_ARCH, target=$DISTRO_ARCH"
    build::install_binfmt || { echo "Error: build::install_binfmt failed" >&2; exit 1; }
    foreign_arch=1
fi

# Download arch bootstrap tarball
ARCH_URL="https://mirror.rackspace.com/archlinux/iso/latest/archlinux-bootstrap-${ARCH_ARCH}.tar.zst"
CACHE_DIR=".cache"
ARCH_TARBALL="${CACHE_DIR}/archlinux-bootstrap-${ARCH_ARCH}.tar.zst"
mkdir -p "$CACHE_DIR"
if [ ! -f "$ARCH_TARBALL" ]; then
    echo "Downloading Arch Linux bootstrap tarball..."
    curl -L -o "$ARCH_TARBALL" "$ARCH_URL"
fi
# Extract bootstrap tarball
echo "Extracting Arch Linux bootstrap tarball..."
mkdir -p "$ROOTFS_DIR"
# extract only the root.x86_64 directory
tar -I zstd -xf "$ARCH_TARBALL" -C "$ROOTFS_DIR" --strip-components=1 "root.${ARCH_ARCH}/"

# Setup bootstrap rootfs
echo "Setting up Arch Linux bootstrap rootfs..."
cp /etc/resolv.conf "$ROOTFS_DIR/etc/resolv.conf"
# Setup pacman servers
cat > "$ROOTFS_DIR/etc/pacman.d/mirrorlist" <<EOF
Server = https://mirror.rackspace.com/archlinux/\$repo/os/\$arch
Server = https://mirror.archlinux32.org/\$repo/os/\$arch
Server = https://mirrors.kernel.org/archlinux/\$repo/os/\$arch
EOF

cache_dir="/var/cache/penv/$DISTRO/$DISTRO_ARCH"
mkdir -p "$cache_dir"
mkdir -p "$ROOTFS_DIR/var/cache/pacman/pkg"
mount --bind "$cache_dir" "$ROOTFS_DIR/var/cache/pacman/pkg"
chown -R 0:0 "$cache_dir"
chmod -R 0755 "$cache_dir"

build::chroot_script "build/arch/prepare.sh"
umount "$ROOTFS_DIR/var/cache/pacman/pkg"

cp "$ROOTFS_DIR/rootfs.tar.gz" "$ROOTFS_DIR/.."
tar_path=$(realpath "$ROOTFS_DIR/../rootfs.tar.gz")
build::prepare_rootfs
mkdir -p "$ROOTFS_DIR"
tar -xzf "$tar_path" -C "$ROOTFS_DIR"
rm "$tar_path"

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

