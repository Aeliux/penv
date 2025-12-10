#!/bin/bash
# OverlayFS Escape Tests
# Tests specific to overlayfs vulnerabilities and escape techniques

test_overlayfs_detection() {
    log_section "OverlayFS Detection Tests"
    
    # Test 1: Detect if using overlayfs
    test_functionality "Root filesystem type" \
        "mount | grep ' / ' | grep -q 'overlay\\|rootfs\\|ext4\\|xfs'"
    
    # Test 2: Check for overlayfs mount options
    if mount | grep -q overlay; then
        test_functionality "OverlayFS is in use" \
            "mount | grep overlay | grep -q 'lowerdir\\|upperdir\\|workdir'"
    else
        log_skip "Not using OverlayFS, skipping some tests"
    fi
}

test_upperdir_access() {
    log_section "OverlayFS Upperdir Tests"
    
    # Test 1: Cannot read upperdir path from mount options
    test_escape_blocked "Cannot extract upperdir path" \
        "mount | grep overlay | grep -o 'upperdir=[^,]*' | cut -d= -f2 | xargs -I {} test -d {} 2>&1"
    
    # Test 2: Cannot access upperdir via /proc/mounts
    test_escape_blocked "Cannot access upperdir from /proc/mounts" \
        "awk '/overlay/ {print \$4}' /proc/mounts | tr ',' '\\n' | grep upperdir | cut -d= -f2 | xargs -I {} ls {} 2>&1"
    
    # Test 3: Cannot write directly to upperdir
    test_escape_blocked "Cannot bypass overlay to write to upperdir" \
        "grep -o 'upperdir=[^,]*' /proc/mounts | head -n1 | cut -d= -f2 | xargs -I {} touch {}/escape 2>&1"
    
    # Test 4: Cannot modify upperdir permissions
    test_escape_blocked "Cannot modify upperdir permissions" \
        "grep -o 'upperdir=[^,]*' /proc/mounts | head -n1 | cut -d= -f2 | xargs -I {} chmod 777 {} 2>&1"
}

test_workdir_access() {
    log_section "OverlayFS Workdir Tests"
    
    # Test 1: Cannot access workdir
    test_escape_blocked "Cannot access overlay workdir" \
        "grep -o 'workdir=[^,]*' /proc/mounts | head -n1 | cut -d= -f2 | xargs -I {} ls {} 2>&1"
    
    # Test 2: Cannot create files in workdir
    test_escape_blocked "Cannot create files in workdir" \
        "grep -o 'workdir=[^,]*' /proc/mounts | head -n1 | cut -d= -f2 | xargs -I {} touch {}/file 2>&1"
    
    # Test 3: Cannot read work directory contents
    test_escape_blocked "Cannot enumerate workdir contents" \
        "mount | grep overlay | grep -o 'workdir=[^,]*' | cut -d= -f2 | xargs -I {} find {} -type f 2>&1"
}

test_lowerdir_access() {
    log_section "OverlayFS Lowerdir Tests"
    
    # Test 1: Cannot access lowerdir directly
    test_escape_blocked "Cannot access lowerdir path" \
        "grep -o 'lowerdir=[^,]*' /proc/mounts | head -n1 | cut -d= -f2 | xargs -I {} ls {} 2>&1"
    
    # Test 2: Cannot modify lowerdir (should be read-only)
    test_escape_blocked "Cannot modify lowerdir" \
        "grep -o 'lowerdir=[^,]*' /proc/mounts | head -n1 | cut -d= -f2 | xargs -I {} touch {}/file 2>&1"
}

test_whiteout_files() {
    log_section "OverlayFS Whiteout Tests"
    
    # Test 1: Cannot create whiteout character device
    test_escape_blocked "Cannot create whiteout device" \
        "mknod /tmp/.wh.test c 0 0 2>&1"
    
    # Test 2: Cannot create opaque directory marker
    test_escape_blocked "Cannot create opaque directory" \
        "mkdir -p /tmp/test && setfattr -n trusted.overlay.opaque -v y /tmp/test 2>&1"
    
    # Test 3: Cannot manipulate whiteout files
    test_escape_blocked "Cannot create .wh.__dir_opaque" \
        "touch /tmp/.wh.__dir_opaque 2>&1 && [ -f /tmp/.wh.__dir_opaque ]"
    
    # Test 4: Cannot use whiteout to hide files
    test_escape_blocked "Cannot use whiteout to delete lower files" \
        "touch /bin/.wh.ls 2>&1"
}

test_overlay_xattr_manipulation() {
    log_section "OverlayFS Extended Attribute Tests"
    
    # Test 1: Cannot set overlay redirect xattr
    test_escape_blocked "Cannot set overlay redirect" \
        "mkdir -p /tmp/test && setfattr -n trusted.overlay.redirect -v '/etc' /tmp/test 2>&1"
    
    # Test 2: Cannot set overlay metacopy xattr
    test_escape_blocked "Cannot set overlay metacopy" \
        "touch /tmp/test && setfattr -n trusted.overlay.metacopy -v y /tmp/test 2>&1"
    
    # Test 3: Cannot read sensitive overlay xattrs
    test_escape_blocked "Cannot read overlay.origin xattr" \
        "getfattr -n trusted.overlay.origin / 2>&1"
    
    # Test 4: Cannot manipulate overlay nlink xattr
    test_escape_blocked "Cannot set overlay nlink" \
        "touch /tmp/test && setfattr -n trusted.overlay.nlink -v 999 /tmp/test 2>&1"
}

test_overlay_mount_manipulation() {
    log_section "OverlayFS Mount Manipulation Tests"
    
    # Test 1: Cannot remount overlay with different options
    test_escape_blocked "Cannot remount overlay" \
        "mount -o remount,rw,upperdir=/tmp/new / 2>&1"
    
    # Test 2: Cannot create new overlay mount
    test_escape_blocked "Cannot create new overlay mount" \
        "mkdir -p /tmp/{lower,upper,work,merged} && mount -t overlay overlay -o lowerdir=/tmp/lower,upperdir=/tmp/upper,workdir=/tmp/work /tmp/merged 2>&1"
    
    # Test 3: Cannot unmount overlay
    test_escape_blocked "Cannot unmount root overlay" \
        "umount / 2>&1"
    
    # Test 4: Cannot pivot_root on overlay
    test_escape_blocked "Cannot pivot_root on overlay" \
        "mkdir -p /tmp/new_root && pivot_root /tmp/new_root /tmp/new_root 2>&1"
}

test_overlay_file_operations() {
    log_section "OverlayFS File Operation Tests"
    
    # Test 1: File creation should work in upperdir (transparent)
    test_functionality "Can create files in overlay" \
        "touch /tmp/testfile && rm /tmp/testfile"
    
    # Test 2: Cannot hardlink across layers
    test_escape_blocked "Cannot hardlink to lower layer" \
        "ln /bin/sh /tmp/sh_link 2>&1 && [ /bin/sh -ef /tmp/sh_link ]"
    
    # Test 3: File deletion creates whiteout (transparent to user)
    test_functionality "File deletion works" \
        "touch /tmp/test && rm /tmp/test && [ ! -f /tmp/test ]"
}

test_overlay_copy_up() {
    log_section "OverlayFS Copy-up Tests"
    
    # Test 1: Modifying lower file should copy-up
    test_functionality "Copy-up works for modifications" \
        "[ -f /etc/hostname ] && cat /etc/hostname > /dev/null"
    
    # Test 2: Cannot exploit copy-up race condition
    test_escape_blocked "Copy-up race protection" \
        "touch /tmp/race && chmod 777 /tmp/race && [ \$(stat -c %a /tmp/race) = '777' ]"
}

test_overlay_metadata() {
    log_section "OverlayFS Metadata Tests"
    
    # Test 1: Cannot access .rootbox-meta
    test_escape_blocked "Cannot read overlay metadata file" \
        "cat /.rootbox-meta 2>&1"
    
    # Test 2: Cannot modify overlay metadata
    test_escape_blocked "Cannot write to overlay metadata" \
        "echo 'hacked' > /.rootbox-meta 2>&1"
    
    # Test 3: Cannot delete overlay metadata
    test_escape_blocked "Cannot delete overlay metadata" \
        "rm /.rootbox-meta 2>&1"
}

test_overlay_permissions() {
    log_section "OverlayFS Permission Tests"
    
    # Test 1: Permission checks are enforced
    test_functionality "File permissions work" \
        "touch /tmp/test && chmod 000 /tmp/test && [ \$(stat -c %a /tmp/test) = '0' ] && rm /tmp/test"
    
    # Test 2: Cannot bypass permission via xattr
    test_escape_blocked "Cannot bypass permissions via xattr" \
        "touch /tmp/test && chmod 000 /tmp/test && setfattr -n user.perms -v 777 /tmp/test 2>&1"
}

test_overlayfs_cve_exploits() {
    log_section "Known OverlayFS CVE Tests"
    
    # Test 1: CVE-2016-1576 (overlayfs permission escalation)
    test_escape_blocked "CVE-2016-1576: Cannot exploit overlay setuid" \
        "mkdir -p /tmp/up && touch /tmp/up/suid && chmod u+s /tmp/up/suid 2>&1"
    
    # Test 2: Check for unsafe overlay features
    test_escape_blocked "Unsafe overlay features disabled" \
        "mount | grep overlay | grep -qv 'redirect_dir=on'"
    
    # Test 3: CVE-2021-3847 (overlay inode hijacking)
    test_escape_blocked "Cannot exploit inode confusion" \
        "mkdir -p /tmp/test && ln /tmp/test /tmp/test2 2>&1"
}

test_overlay_layers() {
    log_section "OverlayFS Layer Tests"
    
    # Test 1: Cannot access lower layers directly
    test_escape_blocked "Cannot traverse to lower layer" \
        "cd / && find . -xdev -name 'lower' 2>&1 | xargs ls 2>&1"
    
    # Test 2: Cannot enumerate layers
    test_escape_blocked "Cannot enumerate overlay layers" \
        "grep overlay /proc/mounts | tr ',' '\\n' | grep lower | wc -l | grep -q '^[5-9]\\|^[1-9][0-9]'"
}

# Run all overlayfs tests
test_overlayfs_detection
test_upperdir_access
test_workdir_access
test_lowerdir_access
test_whiteout_files
test_overlay_xattr_manipulation
test_overlay_mount_manipulation
test_overlay_file_operations
test_overlay_copy_up
test_overlay_metadata
test_overlay_permissions
test_overlayfs_cve_exploits
test_overlay_layers
