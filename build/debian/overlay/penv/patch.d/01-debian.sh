#!/bin/sh
set -e

# Generate C.UTF-8 locale
if command -v locale-gen >/dev/null 2>&1; then
    locale-gen C.UTF-8 2>/dev/null || true
fi

# Prevent doc generation
mkdir -p /etc/dpkg/dpkg.conf.d
cp /etc/dpkg/dpkg.cfg.d/01_nodoc /etc/dpkg/dpkg.conf.d/01_nodoc

# Soft ban man-db
# prepare structure
mkdir -p /tmp/penv/debian-patch/manban/DEBIAN
cat > /tmp/penv/debian-patch/manban/DEBIAN/control <<'EOF'
Package: penv-manban
Version: 1.0
Architecture: all
Maintainer: itsaeliux@gmail.com
Provides: man-db
Conflicts: man-db
Replaces: man-db
Description: Dummy package to block man-db from installing
EOF

# build and install
dpkg-deb --build /tmp/penv/debian-patch/manban /tmp/penv/debian-patch/manban_1.0_all.deb
dpkg -i /tmp/penv/debian-patch/manban_1.0_all.deb
