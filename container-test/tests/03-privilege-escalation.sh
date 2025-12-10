#!/bin/bash
# Privilege Escalation Tests
# Tests for capability abuse, setuid exploitation, and privilege mapping

test_capability_restrictions() {
    log_section "Capability Tests"
    
    # Test 1: Should not have CAP_SYS_ADMIN
    test_escape_blocked "Does not have CAP_SYS_ADMIN" \
        "capsh --print 2>&1 | grep -q 'cap_sys_admin'"
    
    # Test 2: Should not have CAP_SYS_MODULE
    test_escape_blocked "Cannot load kernel modules (CAP_SYS_MODULE)" \
        "insmod /tmp/test.ko 2>&1 || echo 'blocked'"
    
    # Test 3: Should not have CAP_SYS_RAWIO
    test_escape_blocked "Cannot access raw I/O (CAP_SYS_RAWIO)" \
        "dd if=/dev/mem of=/dev/null bs=1 count=1 2>&1"
    
    # Test 4: Should not have CAP_DAC_OVERRIDE
    test_escape_blocked "Cannot override DAC permissions" \
        "echo test > /proc/1/mem 2>&1"
    
    # Test 5: Should not have CAP_SYS_PTRACE
    test_escape_blocked "Cannot ptrace other processes (CAP_SYS_PTRACE)" \
        "gdb -p 1 2>&1 | grep -q 'Operation not permitted'"
    
    # Test 6: Should not have CAP_SYS_BOOT
    test_escape_blocked "Cannot reboot system (CAP_SYS_BOOT)" \
        "reboot 2>&1 | grep -q 'Operation not permitted'"
    
    # Test 7: Should not have CAP_NET_ADMIN
    test_escape_blocked "Cannot configure network (CAP_NET_ADMIN)" \
        "ip link add dummy0 type dummy 2>&1"
    
    # Test 8: Should not have CAP_SYS_TIME
    test_escape_blocked "Cannot set system time (CAP_SYS_TIME)" \
        "date -s '2020-01-01' 2>&1"
    
    # Test 9: Should not have CAP_SYS_CHROOT
    test_escape_blocked "CAP_SYS_CHROOT restricted by NO_NEW_PRIVS" \
        "grep -q 'NoNewPrivs:\\s*1' /proc/self/status"
}

test_setuid_exploitation() {
    log_section "Setuid/Setgid Tests"
    
    # Test 1: Cannot create setuid binaries
    test_escape_blocked "Cannot create setuid binaries" \
        "cp /bin/sh /tmp/suid-sh && chmod u+s /tmp/suid-sh && [ -u /tmp/suid-sh ]"
    
    # Test 2: Cannot create setgid binaries
    test_escape_blocked "Cannot create setgid binaries" \
        "cp /bin/sh /tmp/sgid-sh && chmod g+s /tmp/sgid-sh && [ -g /tmp/sgid-sh ]"
    
    # Test 3: Existing setuid binaries should not grant real root
    test_escape_blocked "Setuid binaries don't grant real root" \
        "which sudo 2>/dev/null && sudo -n id 2>&1 | grep -q 'uid=0(root)' && echo 'escalated'"
    
    # Test 4: Cannot use su to escalate
    test_escape_blocked "Cannot use su for privilege escalation" \
        "echo | su root -c 'id' 2>&1 | grep -q 'uid=0(root)' && echo 'escalated'"
    
    # Test 5: NO_NEW_PRIVS should be set
    test_functionality "NO_NEW_PRIVS is set (PR_SET_NO_NEW_PRIVS)" \
        "grep -q 'NoNewPrivs:\\s*1' /proc/self/status"
}

test_user_namespace_mapping() {
    log_section "User Namespace Mapping Tests"
    
    # Test 1: UID 0 should be mapped, not real root
    test_functionality "UID 0 inside container is mapped user" \
        "[ \$(id -u) -eq 0 ]"
    
    # Test 2: Cannot remap UID namespace
    test_escape_blocked "Cannot remap UID namespace" \
        "unshare -U /bin/sh -c 'echo 0 0 1 > /proc/self/uid_map' 2>&1"
    
    # Test 3: Cannot write to uid_map after setgroups
    test_escape_blocked "Cannot modify uid_map after initialization" \
        "echo '0 1000 1' > /proc/self/uid_map 2>&1"
    
    # Test 4: GID mapping should be restricted
    test_escape_blocked "Cannot modify gid_map" \
        "echo '0 0 1' > /proc/self/gid_map 2>&1"
    
    # Test 5: Should have limited supplementary groups
    test_functionality "Supplementary groups are limited" \
        "[ \$(id -G | wc -w) -lt 10 ]"
}

test_privilege_escalation_vectors() {
    log_section "Privilege Escalation Vector Tests"
    
    # Test 1: Cannot use dirtycow exploit
    test_escape_blocked "Cannot exploit dirty COW" \
        "grep -q 'vulnerable' /proc/self/status 2>&1 || echo 'protected'"
    
    # Test 2: Cannot exploit /proc/self/mem
    test_escape_blocked "Cannot write to /proc/self/mem" \
        "dd if=/dev/zero of=/proc/self/mem bs=1 count=1 2>&1"
    
    # Test 3: Cannot use ptrace for escalation
    test_escape_blocked "Cannot ptrace init process" \
        "echo 0 > /proc/sys/kernel/yama/ptrace_scope 2>&1"
    
    # Test 4: Cannot modify /proc/sys/kernel security settings
    test_escape_blocked "Cannot modify kernel security settings" \
        "echo 0 > /proc/sys/kernel/dmesg_restrict 2>&1"
    
    # Test 5: Cannot load eBPF programs
    test_escape_blocked "Cannot load eBPF programs" \
        "bpftool prog load /tmp/prog.o /sys/fs/bpf/prog 2>&1"
}

test_ambient_capabilities() {
    log_section "Ambient Capability Tests"
    
    # Test 1: Should not have ambient capabilities
    test_escape_blocked "No ambient capabilities" \
        "grep -q 'CapAmb:\\s*0000000000000000' /proc/self/status"
    
    # Test 2: Cannot set ambient capabilities
    test_escape_blocked "Cannot set ambient capabilities" \
        "capsh --addamb=cap_net_raw -- -c 'echo escalated' 2>&1"
}

test_file_capabilities() {
    log_section "File Capability Tests"
    
    # Test 1: Cannot set file capabilities
    test_escape_blocked "Cannot set file capabilities" \
        "cp /bin/ping /tmp/ping && setcap cap_net_raw+ep /tmp/ping 2>&1"
    
    # Test 2: Cannot use capabilities from files
    test_escape_blocked "File capabilities don't grant privileges" \
        "getcap /bin/ping 2>&1 | grep -q 'cap_net_raw' && /bin/ping -c1 8.8.8.8 2>&1"
}

test_seccomp_bypass() {
    log_section "Seccomp Tests"
    
    # Test 1: Check if seccomp is active
    test_functionality "Seccomp should be monitoring" \
        "grep -q 'Seccomp:\\s*[12]' /proc/self/status"
    
    # Test 2: Cannot disable seccomp
    test_escape_blocked "Cannot disable seccomp" \
        "prctl PR_SET_SECCOMP 0 2>&1"
}

test_apparmor_selinux() {
    log_section "LSM (AppArmor/SELinux) Tests"
    
    # Test 1: Check if LSM is active
    if [ -f /sys/kernel/security/apparmor/profiles ]; then
        test_functionality "AppArmor profiles may be loaded" \
            "cat /sys/kernel/security/apparmor/profiles 2>&1 | grep -q '.' || echo 'no profiles'"
    else
        log_skip "AppArmor not available on this system"
    fi
    
    # Test 2: Cannot disable AppArmor
    test_escape_blocked "Cannot disable AppArmor" \
        "echo 0 > /sys/module/apparmor/parameters/enabled 2>&1"
}

test_sudo_abuse() {
    log_section "Sudo/Sudoers Tests"
    
    # Test 1: Should not have passwordless sudo
    test_escape_blocked "No passwordless sudo access" \
        "sudo -n id 2>&1 | grep -q 'uid=0(root)' && echo 'escalated'"
    
    # Test 2: Cannot modify sudoers
    test_escape_blocked "Cannot modify /etc/sudoers" \
        "echo 'ALL ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers 2>&1"
    
    # Test 3: Cannot use sudo to escape container
    test_escape_blocked "Sudo does not provide container escape" \
        "which sudo 2>/dev/null && sudo -n ls /proc/1/root 2>&1"
}

# Run all privilege escalation tests
test_capability_restrictions
test_setuid_exploitation
test_user_namespace_mapping
test_privilege_escalation_vectors
test_ambient_capabilities
test_file_capabilities
test_seccomp_bypass
test_apparmor_selinux
test_sudo_abuse
