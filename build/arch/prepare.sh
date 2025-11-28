#!/bin/sh

set -e

ln -sf /proc/self/mounts /etc/mtab
pacman-key --init
pacman-key --populate archlinux

pacman -Syu --noconfirm

pacstrap -c /mnt \
    glibc \
    bash \
    coreutils \
    filesystem \
    shadow \
    pacman \
    grep \
    nano \
    iputils \
    tar \
    wget \
    which \
    less \
    ed \
    iproute2 \
    procps-ng \
    zip \
    unzip \
    inetutils \
    diffutils \
    dash \
    binutils
