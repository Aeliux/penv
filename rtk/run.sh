#!/bin/env bash

set -e

rootfs="$1"
shift

set -x
qemu-system-x86_64 -kernel arch/x86/boot/bzImage -m 64M -accel kvm -machine pc -append "quiet" -virtfs local,path="$rootfs",mount_tag=host0,security_model=none "$@"
