#!/bin/env bash

set -e

cleanup() {
    [ -n "$QEMU_PID" ] && kill "$QEMU_PID" 2>/dev/null || true
}
trap cleanup EXIT INT TERM

rootfs="$1"
shift

QEMU_OUT=$(mktemp)
set -x
qemu-system-x86_64 \
	-kernel arch/x86/boot/bzImage \
	-m 64M -accel kvm \
	-machine pc \
	-append "quiet" \
	-virtfs local,path="$rootfs",mount_tag=host0,security_model=none \
	-serial pty \
	-display none \
	-nic user,model=virtio \
	"$@" \
	1> "$QEMU_OUT" 2>1 &

set +x
QEMU_PID=$!

# Extract PTY path
while :; do
    PTY=$(grep -o '/dev/pts/[0-9]\+' "$QEMU_OUT" | tail -n1)
    [ -n "$PTY" ] && break
    sleep 0.05
done

echo "Connected to VM serial on $PTY"

# Attach terminal (raw mode, no echo)
#socat /dev/tty "FILE:$PTY,raw,echo=0" &
#SOCAT_PID=$!
#wait "$SOCAT_PID"

# Attach with screen
screen "$PTY"
