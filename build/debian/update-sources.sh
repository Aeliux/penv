#!/bin/sh

# Update package sources in the rootfs
# Must be ran inside rootfs

set -eu

if [ "$#" -ne 3 ]; then
  echo "Usage: $0 <distro> <release> <mirror>" >&2
  exit 1
fi

DISTRO=$1
DISTRO_RELEASE=$2
MIRROR=$3

case "$DISTRO" in
  ubuntu)
    cat > /etc/apt/sources.list <<EOF
deb $MIRROR $DISTRO_RELEASE main universe multiverse
deb $MIRROR $DISTRO_RELEASE-updates main universe multiverse
deb $MIRROR $DISTRO_RELEASE-backports main universe multiverse
EOF
    # Add security repos that did not start with ports.ubuntu.com
    if ! echo "$MIRROR" | grep -q "ports.ubuntu.com"; then
      echo "deb http://security.ubuntu.com/ubuntu $DISTRO_RELEASE-security main universe multiverse" >> /etc/apt/sources.list
    else
      echo "deb $MIRROR $DISTRO_RELEASE-security main universe multiverse" >> /etc/apt/sources.list
    fi
    ;;
  debian)
    cat > /etc/apt/sources.list <<EOF
deb $MIRROR $DISTRO_RELEASE main
deb $MIRROR $DISTRO_RELEASE-updates main
deb http://security.debian.org/ $DISTRO_RELEASE-security main
EOF
    # Add backports for all except bullseye
    if [ "$DISTRO_RELEASE" != "bullseye" ]; then
      echo "deb $MIRROR $DISTRO_RELEASE-backports main" >> /etc/apt/sources.list
    fi
    ;;
esac

apt-get update
apt-get upgrade -y
apt-get autoremove -y --purge
