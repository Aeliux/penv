#!/bin/sh

set -e

mount --bind / /
ln -sf /proc/self/mounts /etc/mtab
pacman-key --init
pacman-key --populate archlinux

pacman -Syu --noconfirm

pacstrap -c /mnt glibc bash coreutils filesystem shadow pacman
tar czf /rootfs.tar.gz -C /mnt .
umount /