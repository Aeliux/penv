#!/bin/bash
# Filesystem Escape Tests
# Tests for chroot escapes, path traversal, and mount manipulation

test_chroot_escape_techniques() {
    log_section "Chroot Escape Tests"
    
    # Test 1: Classic chroot escape via chroot/chdir
    test_escape_blocked "Cannot escape via double chroot" \
        "mkdir -p /tmp/escape && chroot /tmp/escape /bin/sh -c 'cd / && chroot . /bin/sh -c pwd' 2>&1"
    
    # Test 2: Escape via creating new root
    test_escape_blocked "Cannot escape by creating new root" \
        "mkdir -p /tmp/newroot && chroot /tmp/newroot /bin/sh -c 'echo escaped' 2>&1"
    
    # Test 3: Escape via pivot_root
    test_escape_blocked "Cannot escape via pivot_root" \
        "pivot_root . . 2>&1"
    
    # Test 4: Escape via /proc/self/root
    test_escape_blocked "Cannot escape via /proc/self/root" \
        "[ -d /proc/self/root ] && cd /proc/self/root && pwd | grep -qv '^/$'"
    
    # Test 5: Escape via /proc/self/cwd
    test_escape_blocked "Cannot escape via /proc/self/cwd" \
        "cd /proc/self/cwd/../../.. && pwd | grep -qv '^/$'"
    
    # Test 6: Cannot break chroot with fchdir
    test_escape_blocked "Cannot use fchdir to escape" \
        "cd / && mkdir -p /test && cd /test && cd .. && pwd | grep -qv '^/$'"
}

test_path_traversal() {
    log_section "Path Traversal Tests"
    
    # Test 1: Cannot traverse to host root
    test_escape_blocked "Cannot traverse to host root via ../" \
        "cd ../../../../../../../../ && ls -la / 2>&1 | grep -q 'boot\\|home\\|root' && echo 'escaped'"
    
    # Test 2: Symlink following should be contained
    test_escape_blocked "Cannot follow symlinks to host" \
        "ln -s /../../../etc/passwd /tmp/hostpasswd 2>&1 && cat /tmp/hostpasswd 2>&1"
    
    # Test 3: Cannot create symlink to host paths
    test_escape_blocked "Cannot create symlinks outside container" \
        "ln -s /../../../../bin/bash /tmp/hostbash 2>&1 && /tmp/hostbash -c 'echo escaped' 2>&1"
    
    # Test 4: Hardlink restrictions
    test_escape_blocked "Cannot create hardlinks to host files" \
        "ln /../../../etc/shadow /tmp/hostshadow 2>&1 && cat /tmp/hostshadow 2>&1"
}

test_mount_manipulation() {
    log_section "Mount Manipulation Tests"
    
    # Test 1: Cannot mount new filesystems
    test_escape_blocked "Cannot mount arbitrary filesystem" \
        "mount -t tmpfs tmpfs /mnt 2>&1"
    
    # Test 2: Cannot bind mount host directories
    test_escape_blocked "Cannot bind mount host directories" \
        "mount --bind /../../../ /mnt 2>&1"
    
    # Test 3: Cannot mount /proc with custom options
    test_escape_blocked "Cannot remount /proc with custom options" \
        "mount -t proc -o rw,nosuid,nodev,noexec,relatime proc /proc 2>&1"
    
    # Test 4: Cannot umount critical mounts
    test_escape_blocked "Cannot umount /proc" \
        "umount /proc 2>&1 && [ ! -d /proc/self ]"
    
    # Test 5: Cannot move mounts
    test_escape_blocked "Cannot move mounts" \
        "mkdir -p /tmp/newproc && mount --move /proc /tmp/newproc 2>&1"
    
    # Test 6: Cannot create mount namespace
    test_escape_blocked "Cannot create new mount namespace" \
        "unshare -m /bin/sh -c 'echo escaped' 2>&1"
}

test_filesystem_access() {
    log_section "Filesystem Access Tests"
    
    # Test 1: Root filesystem should be contained
    test_functionality "Root directory is container root" \
        "[ \$(ls -la / | wc -l) -lt 100 ]"
    
    # Test 2: Cannot access /proc/sys/kernel on host
    test_escape_blocked "Cannot access host /proc/sys" \
        "cat /proc/1/root/proc/sys/kernel/hostname 2>&1"
    
    # Test 3: Cannot read from /proc/kcore
    test_escape_blocked "Cannot read kernel memory via /proc/kcore" \
        "dd if=/proc/kcore of=/dev/null bs=1 count=1 2>&1"
    
    # Test 4: Cannot access host /sys
    test_escape_blocked "Cannot access host /sys directly" \
        "[ -d /sys/class/net ] && ls /sys/class/net | grep -q 'eth0\\|wlan0\\|enp'"
}

test_special_files() {
    log_section "Special File Tests"
    
    # Test 1: Cannot access /proc/kallsyms
    test_escape_blocked "Cannot read kernel symbols" \
        "grep -q 'T sys_' /proc/kallsyms 2>&1"
    
    # Test 2: Cannot access /proc/modules
    test_escape_blocked "Cannot see kernel modules" \
        "cat /proc/modules 2>&1 | head -n1 | grep -q '^[a-z]'"
    
    # Test 3: Cannot write to /proc/self/exe
    test_escape_blocked "Cannot modify /proc/self/exe" \
        "echo test > /proc/self/exe 2>&1"
    
    # Test 4: Cannot access /proc/self/fd outside container
    test_escape_blocked "File descriptors are isolated" \
        "ls -la /proc/self/fd/0 2>&1 | grep -qv '/dev/'"
}

test_overlay_escapes() {
    log_section "Overlay/Union Filesystem Tests"
    
    # Test 1: Cannot access upperdir from inside
    test_escape_blocked "Cannot access overlay upperdir" \
        "mount | grep overlay | awk '{print \$6}' | grep -o 'upperdir=[^,]*' | cut -d= -f2 | head -n1 | xargs -I {} ls {} 2>&1"
    
    # Test 2: Cannot access workdir
    test_escape_blocked "Cannot access overlay workdir" \
        "mount | grep overlay | awk '{print \$6}' | grep -o 'workdir=[^,]*' | cut -d= -f2 | head -n1 | xargs -I {} ls {} 2>&1"
    
    # Test 3: Cannot manipulate whiteout files
    test_escape_blocked "Cannot create whiteout files" \
        "mknod /tmp/.wh.test c 0 0 2>&1"
}

test_file_operations() {
    log_section "File Operation Tests"
    
    # Test 1: Cannot create files in read-only mounts
    test_escape_blocked "Cannot write to /sys" \
        "echo 1 > /sys/test 2>&1"
    
    # Test 2: /tmp should be writable
    test_functionality "/tmp is writable" \
        "echo test > /tmp/testfile && rm /tmp/testfile"
    
    # Test 3: Cannot change mount attributes
    test_escape_blocked "Cannot change mount attributes" \
        "mount -o remount,rw,suid,dev,exec / 2>&1"
}

# Run all filesystem tests
test_chroot_escape_techniques
test_path_traversal
test_mount_manipulation
test_filesystem_access
test_special_files
test_overlay_escapes
test_file_operations
