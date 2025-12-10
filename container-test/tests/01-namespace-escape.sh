#!/bin/bash
# Namespace Escape Tests
# Tests for PID, mount, user, UTS, IPC, and network namespace isolation

test_pid_namespace_isolation() {
    log_section "PID Namespace Tests"
    
    # Test 1: Container should not see host PIDs
    test_escape_blocked "Cannot see host PIDs in /proc" \
        "test -d /proc/1 && ls /proc | grep -q '^[0-9]' && [ \$(ls /proc | grep -c '^[0-9]') -lt 100 ]"
    
    # Test 2: Container PID 1 should be init process
    test_functionality "Container has its own PID namespace" \
        "[ \$(cat /proc/self/pid 2>/dev/null || echo 1) -le 10 ]"
    
    # Test 3: Cannot access host PID namespace via /proc/1/ns/pid
    test_escape_blocked "Cannot escape via /proc/1/ns/pid" \
        "readlink /proc/1/ns/pid | grep -v 'pid:\['"
    
    # Test 4: Cannot use nsenter to escape PID namespace
    test_escape_blocked "Cannot nsenter into host PID namespace" \
        "nsenter -t 1 -p /bin/sh -c 'echo escaped' 2>&1"
    
    # Test 5: /proc/sys should be restricted
    test_escape_blocked "Cannot write to /proc/sys" \
        "echo 1 > /proc/sys/kernel/random/entropy_avail 2>&1"
}

test_mount_namespace_isolation() {
    log_section "Mount Namespace Tests"
    
    # Test 1: Should not see host mounts
    test_escape_blocked "Cannot see host root in mount table" \
        "mount | grep -q ' / ' && mount | grep ' / ' | grep -qv 'overlay\\|rootfs\\|tmpfs'"
    
    # Test 2: Cannot remount root as rw
    test_escape_blocked "Cannot remount root as read-write" \
        "mount -o remount,rw / 2>&1"
    
    # Test 3: Cannot create new mount namespace
    test_escape_blocked "Cannot unshare mount namespace" \
        "unshare -m /bin/sh -c 'echo escaped' 2>&1"
    
    # Test 4: Cannot access host filesystem via /proc/1/root
    test_escape_blocked "Cannot access host root via /proc/1/root" \
        "ls /proc/1/root 2>&1 | grep -qv 'Permission denied\\|No such file'"
    
    # Test 5: Mount propagation should be private
    test_escape_blocked "Mount propagation is private" \
        "grep -q 'shared\\|master' /proc/self/mountinfo"
}

test_user_namespace_isolation() {
    log_section "User Namespace Tests"
    
    # Test 1: UID mapping should be restricted
    test_functionality "UID is mapped to 0 inside container" \
        "[ \$(id -u) -eq 0 ]"
    
    # Test 2: Cannot write to uid_map
    test_escape_blocked "Cannot modify uid_map" \
        "echo '0 0 4294967295' > /proc/self/uid_map 2>&1"
    
    # Test 3: Cannot escalate to real root
    test_escape_blocked "Cannot access real UID 0 capabilities" \
        "[ \$(cat /proc/self/uid_map | head -n1 | awk '{print \$2}') -eq 0 ]"
    
    # Test 4: /proc/self/setgroups should be deny
    test_functionality "setgroups is denied" \
        "grep -q 'deny' /proc/self/setgroups 2>/dev/null"
}

test_uts_namespace_isolation() {
    log_section "UTS Namespace Tests"
    
    # Test 1: Hostname should be containerized
    test_functionality "Hostname is isolated (rootbox or rootbox-ofs)" \
        "hostname | grep -q 'rootbox'"
    
    # Test 2: Cannot see host hostname
    test_escape_blocked "Cannot read host hostname" \
        "[ \$(hostname) = 'localhost' -o \$(hostname) = \$(cat /proc/sys/kernel/hostname 2>/dev/null) ]"
    
    # Test 3: Cannot modify hostname to bypass restrictions
    test_escape_blocked "Cannot set arbitrary hostname" \
        "hostname attacker-host 2>&1 && [ \$(hostname) = 'attacker-host' ]"
}

test_ipc_namespace_isolation() {
    log_section "IPC Namespace Tests"
    
    # Test 1: Should have isolated IPC namespace
    test_functionality "IPC namespace is isolated" \
        "[ -d /proc/sys/kernel ] && [ -f /proc/sys/kernel/shmmni ]"
    
    # Test 2: Cannot see host shared memory
    test_escape_blocked "Cannot access host shared memory" \
        "ipcs -m 2>&1 | grep -v 'key\\|^$' | wc -l | grep -q '^0$'"
    
    # Test 3: Cannot access host message queues
    test_escape_blocked "Cannot access host message queues" \
        "ipcs -q 2>&1 | grep -v 'key\\|^$' | wc -l | grep -q '^0$'"
    
    # Test 4: Cannot access host semaphores
    test_escape_blocked "Cannot access host semaphores" \
        "ipcs -s 2>&1 | grep -v 'key\\|^$' | wc -l | grep -q '^0$'"
}

test_namespace_links() {
    log_section "Namespace Link Tests"
    
    # Test 1: Namespace links should be isolated
    test_functionality "Has isolated namespace links" \
        "[ -L /proc/self/ns/pid ] && [ -L /proc/self/ns/mnt ]"
    
    # Test 2: Cannot access parent namespace
    test_escape_blocked "Cannot access parent namespace via .." \
        "ls /proc/self/ns/../../../ 2>&1"
    
    # Test 3: Cannot setns into host namespace
    test_escape_blocked "Cannot setns into host namespace" \
        "setns 2>&1 | grep -q 'not found\\|Permission denied'"
}

# Run all namespace tests
test_pid_namespace_isolation
test_mount_namespace_isolation
test_user_namespace_isolation
test_uts_namespace_isolation
test_ipc_namespace_isolation
test_namespace_links
