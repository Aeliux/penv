#!/usr/bin/env bash
# Build and install proot from source
# 
# Ubuntu/Debian ships with proot 5.1.0 which has a critical bug:
# Relative paths fail after cd in glibc-based distributions.
# 
# This bug is fixed in proot v5.4.0+
# See: https://github.com/proot-me/proot

set -e

PROOT_VERSION="${PROOT_VERSION:-v5.4.0}"
BUILD_DIR="${BUILD_DIR:-/tmp/proot-build}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

echo "=== Building proot ${PROOT_VERSION} ==="

# Install build dependencies
echo "Installing build dependencies..."
sudo apt-get update -qq
sudo apt-get install -y -qq \
    build-essential \
    git \
    libtalloc-dev \
    libarchive-dev \
    python3 \
    uthash-dev \
    pkg-config

# Clone source
echo "Cloning proot source..."
rm -rf "$BUILD_DIR"
git clone --depth 1 --branch "$PROOT_VERSION" \
    https://github.com/proot-me/proot.git "$BUILD_DIR"

# Build
echo "Building proot..."
cd "$BUILD_DIR/src"
make -j$(nproc)

# Test
echo "Testing proot..."
./proot --version

# Install
echo "Installing to ${INSTALL_DIR}..."
sudo cp proot "${INSTALL_DIR}/proot-${PROOT_VERSION#v}"
sudo chmod +x "${INSTALL_DIR}/proot-${PROOT_VERSION#v}"
sudo ln -sf "${INSTALL_DIR}/proot-${PROOT_VERSION#v}" "${INSTALL_DIR}/proot"

# Verify
echo ""
echo "=== Installation complete ==="
proot --version
echo ""
echo "Installed at: $(which proot)"
