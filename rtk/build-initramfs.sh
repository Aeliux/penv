#!/bin/env bash

set -e

cd "$(dirname "$0")"
mkdir -p out
cd out

# Create initial tree
mkdir -p dev/pts etc proc sys tmp

# Create devices
[ -e dev/console ] || mknod -m 600 dev/console c 5 1
[ -e dev/null ]    || mknod -m 666 dev/null c 1 3
[ -e dev/tty ]     || mknod -m 666 dev/tty c 5 0

# Copy root dir
cp -a ../root/. .

chown -R root:root .

find . | cpio -oH newc > ../out.cpio

chmod 777 ../out.cpio
