#!/usr/bin/env bash
# Build and install proot from source

set -e

PROOT_VERSION="${PROOT_VERSION:-v5.4.0}"
BUILD_DIR="${BUILD_DIR:-/tmp/proot-build}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

echo "Building proot ${PROOT_VERSION}"

# Install build dependencies only for Debian/Ubuntu and with root permissions
if command -v apt-get >/dev/null 2>&1 && [ "$(id -u)" -eq 0 ]; then
    echo "Installing build dependencies..."
    apt-get update -qq
    apt-get install -y -qq \
        build-essential \
        git \
        libtalloc-dev \
        libarchive-dev \
        python3 \
        uthash-dev \
        pkg-config
fi

# Clone source
echo "Cloning proot source..."
rm -rf "$BUILD_DIR"
git clone --depth 1 --branch "$PROOT_VERSION" \
    https://github.com/proot-me/proot.git "$BUILD_DIR"

# Build
echo "Building proot..."
cd "$BUILD_DIR/src"
make -j$(nproc)

# Install
echo "Installing to ${INSTALL_DIR}..."
cp proot "${INSTALL_DIR}/proot-${PROOT_VERSION#v}"
chmod +x "${INSTALL_DIR}/proot-${PROOT_VERSION#v}"
ln -sf "${INSTALL_DIR}/proot-${PROOT_VERSION#v}" "${INSTALL_DIR}/proot"

echo "Proot ${PROOT_VERSION} compiled successfully."
