#!/bin/bash
# Device Access Tests
# Tests for device node creation, raw disk access, and device manipulation

test_device_node_creation() {
    log_section "Device Node Creation Tests"
    
    # Test 1: Cannot create block device nodes
    test_escape_blocked "Cannot create block device nodes (sda)" \
        "mknod /tmp/sda b 8 0 2>&1"
    
    # Test 2: Cannot create character device nodes
    test_escape_blocked "Cannot create char device nodes (mem)" \
        "mknod /tmp/mem c 1 1 2>&1"
    
    # Test 3: Cannot create device nodes for host disks
    test_escape_blocked "Cannot create nvme device node" \
        "mknod /tmp/nvme0n1 b 259 0 2>&1"
    
    # Test 4: Cannot create kmem device
    test_escape_blocked "Cannot create kmem device node" \
        "mknod /tmp/kmem c 1 2 2>&1"
    
    # Test 5: Cannot create port device
    test_escape_blocked "Cannot create port device node" \
        "mknod /tmp/port c 1 4 2>&1"
}

test_raw_disk_access() {
    log_section "Raw Disk Access Tests"
    
    # Test 1: Cannot read from /dev/sda
    test_escape_blocked "Cannot read from /dev/sda" \
        "dd if=/dev/sda of=/dev/null bs=512 count=1 2>&1"
    
    # Test 2: Cannot write to /dev/sda
    test_escape_blocked "Cannot write to /dev/sda" \
        "dd if=/dev/zero of=/dev/sda bs=512 count=1 2>&1"
    
    # Test 3: Cannot access /dev/nvme devices
    test_escape_blocked "Cannot access nvme devices" \
        "ls /dev/nvme* 2>&1 && dd if=/dev/nvme0n1 of=/dev/null bs=1 count=1 2>&1"
    
    # Test 4: Cannot access loop devices
    test_escape_blocked "Cannot access loop devices" \
        "losetup /dev/loop0 /tmp/test.img 2>&1"
    
    # Test 5: Cannot access dm devices
    test_escape_blocked "Cannot access device mapper" \
        "dmsetup create test 2>&1"
}

test_memory_device_access() {
    log_section "Memory Device Access Tests"
    
    # Test 1: Cannot read from /dev/mem
    test_escape_blocked "Cannot read from /dev/mem" \
        "dd if=/dev/mem of=/dev/null bs=1 count=1 2>&1"
    
    # Test 2: Cannot write to /dev/mem
    test_escape_blocked "Cannot write to /dev/mem" \
        "dd if=/dev/zero of=/dev/mem bs=1 count=1 2>&1"
    
    # Test 3: Cannot read from /dev/kmem
    test_escape_blocked "Cannot read from /dev/kmem" \
        "dd if=/dev/kmem of=/dev/null bs=1 count=1 2>&1"
    
    # Test 4: Cannot access /dev/port
    test_escape_blocked "Cannot access /dev/port" \
        "dd if=/dev/port of=/dev/null bs=1 count=1 2>&1"
}

test_tty_pty_manipulation() {
    log_section "TTY/PTY Manipulation Tests"
    
    # Test 1: Should have access to own PTY
    test_functionality "Has access to own PTY" \
        "[ -c /dev/pts/0 ] || [ -c /dev/console ]"
    
    # Test 2: Cannot access host TTY
    test_escape_blocked "Cannot access /dev/tty0" \
        "echo test > /dev/tty0 2>&1"
    
    # Test 3: Cannot steal other TTYs
    test_escape_blocked "Cannot access /dev/tty1" \
        "cat /dev/tty1 2>&1"
    
    # Test 4: Cannot manipulate console
    test_escape_blocked "Cannot write to /dev/console from another process" \
        "echo '\033[2J' > /dev/console 2>&1"
}

test_device_permissions() {
    log_section "Device Permission Tests"
    
    # Test 1: /dev permissions should be restricted
    test_functionality "/dev is mounted" \
        "[ -d /dev ]"
    
    # Test 2: Cannot change device permissions
    test_escape_blocked "Cannot chmod devices" \
        "chmod 777 /dev/null 2>&1"
    
    # Test 3: Cannot chown devices
    test_escape_blocked "Cannot chown devices" \
        "chown nobody:nogroup /dev/null 2>&1"
    
    # Test 4: Cannot create device in /tmp
    test_escape_blocked "Cannot create device in /tmp" \
        "mknod /tmp/null c 1 3 2>&1"
}

test_device_mounting() {
    log_section "Device Mounting Tests"
    
    # Test 1: Cannot mount host block devices
    test_escape_blocked "Cannot mount /dev/sda" \
        "mkdir -p /mnt/escape && mount /dev/sda1 /mnt/escape 2>&1"
    
    # Test 2: Cannot mount by UUID
    test_escape_blocked "Cannot mount by UUID" \
        "mount UUID=fake-uuid /mnt 2>&1"
    
    # Test 3: Cannot mount by LABEL
    test_escape_blocked "Cannot mount by LABEL" \
        "mount LABEL=fake-label /mnt 2>&1"
    
    # Test 4: Cannot create loopback mounts
    test_escape_blocked "Cannot create loop mount" \
        "mount -o loop /tmp/image.img /mnt 2>&1"
}

test_usb_device_access() {
    log_section "USB Device Access Tests"
    
    # Test 1: Cannot access USB devices
    test_escape_blocked "Cannot access /dev/bus/usb" \
        "ls /dev/bus/usb 2>&1 && echo 'accessible'"
    
    # Test 2: Cannot enumerate USB devices
    test_escape_blocked "Cannot enumerate USB via /sys" \
        "ls /sys/bus/usb/devices 2>&1 | grep -q '[0-9]'"
    
    # Test 3: Cannot unbind USB drivers
    test_escape_blocked "Cannot unbind USB drivers" \
        "echo '1-1' > /sys/bus/usb/drivers/usb/unbind 2>&1"
}

test_graphics_device_access() {
    log_section "Graphics Device Access Tests"
    
    # Test 1: Cannot access DRI devices
    test_escape_blocked "Cannot access /dev/dri" \
        "ls /dev/dri 2>&1 && dd if=/dev/dri/card0 of=/dev/null bs=1 count=1 2>&1"
    
    # Test 2: Cannot access framebuffer
    test_escape_blocked "Cannot access /dev/fb0" \
        "dd if=/dev/zero of=/dev/fb0 bs=1 count=1 2>&1"
    
    # Test 3: Cannot access GPU devices
    test_escape_blocked "Cannot access /dev/nvidia*" \
        "ls /dev/nvidia* 2>&1 && cat /dev/nvidia0 2>&1"
}

test_input_device_access() {
    log_section "Input Device Access Tests"
    
    # Test 1: Cannot access keyboard input
    test_escape_blocked "Cannot access /dev/input/event*" \
        "cat /dev/input/event0 2>&1"
    
    # Test 2: Cannot access mouse input
    test_escape_blocked "Cannot access /dev/input/mouse0" \
        "cat /dev/input/mouse0 2>&1"
    
    # Test 3: Cannot inject input events
    test_escape_blocked "Cannot write to input devices" \
        "echo 'test' > /dev/input/event0 2>&1"
}

test_network_device_access() {
    log_section "Network Device Access Tests"
    
    # Test 1: Cannot access TUN/TAP devices
    test_escape_blocked "Cannot open /dev/net/tun" \
        "cat /dev/net/tun 2>&1"
    
    # Test 2: Cannot create TUN interface
    test_escape_blocked "Cannot create TUN interface" \
        "ip tuntap add mode tun dev tun0 2>&1"
    
    # Test 3: Cannot access raw sockets
    test_escape_blocked "Cannot create raw socket" \
        "python3 -c 'import socket; socket.socket(socket.AF_PACKET, socket.SOCK_RAW)' 2>&1"
}

test_special_devices() {
    log_section "Special Device Tests"
    
    # Test 1: /dev/zero should work
    test_functionality "/dev/zero is accessible" \
        "dd if=/dev/zero of=/dev/null bs=1 count=1 2>&1"
    
    # Test 2: /dev/null should work
    test_functionality "/dev/null is accessible" \
        "echo test > /dev/null"
    
    # Test 3: /dev/urandom should work
    test_functionality "/dev/urandom is accessible" \
        "dd if=/dev/urandom of=/dev/null bs=1 count=1 2>&1"
    
    # Test 4: Cannot access /dev/random entropy
    test_escape_blocked "Cannot drain /dev/random" \
        "dd if=/dev/random of=/dev/null bs=1M count=100 2>&1"
}

test_nvme_specific() {
    log_section "NVMe Device Tests"
    
    # Test 1: Cannot access NVMe admin interface
    test_escape_blocked "Cannot access NVMe character devices" \
        "ls /dev/ng* 2>&1 && cat /dev/ng0n1 2>&1"
    
    # Test 2: Cannot send NVMe admin commands
    test_escape_blocked "Cannot send NVMe commands" \
        "nvme list 2>&1 | grep -q '/dev/nvme'"
}

test_scsi_devices() {
    log_section "SCSI Device Tests"
    
    # Test 1: Cannot access SCSI generic devices
    test_escape_blocked "Cannot access /dev/sg*" \
        "ls /dev/sg* 2>&1 && dd if=/dev/sg0 of=/dev/null bs=1 count=1 2>&1"
    
    # Test 2: Cannot send SCSI commands
    test_escape_blocked "Cannot send SCSI commands" \
        "sg_inq /dev/sda 2>&1"
}

# Run all device access tests
test_device_node_creation
test_raw_disk_access
test_memory_device_access
test_tty_pty_manipulation
test_device_permissions
test_device_mounting
test_usb_device_access
test_graphics_device_access
test_input_device_access
test_network_device_access
test_special_devices
test_nvme_specific
test_scsi_devices
