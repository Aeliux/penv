#!/usr/bin/env bash

set -euo pipefail

# build/fix-perm.sh
# This script fixes permissions in the rootfs directory.
# It should be run with the rootfs directory as the first argument.

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <rootfs-directory>" >&2
    exit 1
fi

ROOTFS_DIR=$1

# Fix permissions for proot compatibility
echo "Setting correct permissions for proot..."
# Ensure critical directories have proper permissions
chmod 755 "$ROOTFS_DIR" 2>/dev/null || true
chmod 755 "$ROOTFS_DIR/bin" 2>/dev/null || true
chmod 755 "$ROOTFS_DIR/usr" "$ROOTFS_DIR/usr/bin" 2>/dev/null || true
chmod 755 "$ROOTFS_DIR/sbin" "$ROOTFS_DIR/usr/sbin" 2>/dev/null || true
chmod 755 "$ROOTFS_DIR/lib" 2>/dev/null || true
chmod 755 "$ROOTFS_DIR/etc" 2>/dev/null || true
chmod 1777 "$ROOTFS_DIR/tmp" 2>/dev/null || true
chmod 755 "$ROOTFS_DIR/var" 2>/dev/null || true
chmod 755 "$ROOTFS_DIR/opt" 2>/dev/null || true

# Fix /root directory permissions
if [ -d "$ROOTFS_DIR/root" ]; then
    chmod 700 "$ROOTFS_DIR/root"
fi

# Ensure all executables in bin directories are executable
find "$ROOTFS_DIR/bin" "$ROOTFS_DIR/sbin" "$ROOTFS_DIR/usr/bin" "$ROOTFS_DIR/usr/sbin" \
    -type f -executable 2>/dev/null | while read -r file; do
    chmod 755 "$file" 2>/dev/null || true
done

# Fix library permissions
find "$ROOTFS_DIR/lib" "$ROOTFS_DIR/usr/lib" -type f -name "*.so*" 2>/dev/null | while read -r file; do
    chmod 644 "$file" 2>/dev/null || true
done

# Fix dynamic linker permissions (critical for execution)
find "$ROOTFS_DIR" -type f \( -name "ld-linux*.so.*" -o -name "ld64.so.*" -o -name "ld-*.so" \) 2>/dev/null | while read -r file; do
    chmod 755 "$file" 2>/dev/null || true
done

# Ensure penv scripts are executable
chmod 755 "$ROOTFS_DIR/penv" 2>/dev/null || true
find "$ROOTFS_DIR/penv" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
find "$ROOTFS_DIR/penv/startup.d" -type f -exec chmod 755 {} \; 2>/dev/null || true

# Fix device directory permissions (if exists)
if [ -d "$ROOTFS_DIR/dev" ]; then
    chmod 755 "$ROOTFS_DIR/dev"
fi