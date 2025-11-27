#!/bin/sh
set -e

# Generate C.UTF-8 locale
if command -v locale-gen >/dev/null 2>&1; then
    locale-gen C.UTF-8 2>/dev/null || true
fi

# Soft block init scripts from running during package installation
cat > "/usr/sbin/policy-rc.d" <<'EOF'
#!/bin/sh
# refuse to start/stop services during package installations
exit 101
EOF
  chmod 0755 "/usr/sbin/policy-rc.d"

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
Priority: required
Essential: yes
Provides: man-db, man
Conflicts: man-db, man
Replaces: man-db, man
Description: Dummy package to block man from installing
EOF

# build and install
dpkg-deb --build /tmp/penv/debian-patch/manban /tmp/penv/debian-patch/manban_1.0_all.deb
dpkg -i /tmp/penv/debian-patch/manban_1.0_all.deb
