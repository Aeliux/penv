#!/bin/sh

# Update package sources in the rootfs
# Must be ran inside rootfs

set -e

DISTRO=$1
DISTRO_RELEASE=$2
MIRROR=$3

case "$DISTRO" in
  ubuntu)
    cat > /etc/apt/sources.list <<EOF
    deb $MIRROR $DISTRO_RELEASE main universe multiverse
    deb $MIRROR $DISTRO_RELEASE-updates main universe multiverse
    deb http://security.debian.org/ $DISTRO_RELEASE-security main universe multiverse
    deb $MIRROR $DISTRO_RELEASE-backports main universe multiverse
EOF
    ;;
  debian)
    cat > /etc/apt/sources.list <<EOF
    deb $MIRROR $DISTRO_RELEASE main
    deb $MIRROR $DISTRO_RELEASE-updates main
    deb http://security.debian.org/ $DISTRO_RELEASE-security main
    deb $MIRROR $DISTRO_RELEASE-backports main
EOF
    ;;
esac

apt-get update
apt-get upgrade -y
apt-get autoremove -y --purge
