#!/bin/bash
# Procfs/Sysfs Tests
# Tests for /proc and /sys manipulation and kernel interface exploitation

test_proc_sys_kernel() {
    log_section "/proc/sys/kernel Tests"
    
    # Test 1: Cannot modify kernel parameters
    test_escape_blocked "Cannot modify sysctl kernel.hostname" \
        "echo hacked > /proc/sys/kernel/hostname 2>&1"
    
    # Test 2: Cannot trigger SysRq
    test_escape_blocked "Cannot trigger SysRq commands" \
        "echo h > /proc/sysrq-trigger 2>&1"
    
    # Test 3: Cannot modify panic settings
    test_escape_blocked "Cannot modify kernel.panic" \
        "echo 0 > /proc/sys/kernel/panic 2>&1"
    
    # Test 4: Cannot modify dmesg restrictions
    test_escape_blocked "Cannot disable dmesg_restrict" \
        "echo 0 > /proc/sys/kernel/dmesg_restrict 2>&1"
    
    # Test 5: Cannot modify kptr_restrict
    test_escape_blocked "Cannot modify kptr_restrict" \
        "echo 0 > /proc/sys/kernel/kptr_restrict 2>&1"
    
    # Test 6: Cannot modify perf_event_paranoid
    test_escape_blocked "Cannot modify perf_event_paranoid" \
        "echo -1 > /proc/sys/kernel/perf_event_paranoid 2>&1"
}

test_proc_special_files() {
    log_section "/proc Special File Tests"
    
    # Test 1: Cannot read /proc/kcore
    test_escape_blocked "Cannot read kernel memory via /proc/kcore" \
        "dd if=/proc/kcore of=/dev/null bs=1 count=1 2>&1"
    
    # Test 2: Cannot read /proc/kallsyms with addresses
    test_escape_blocked "Cannot read kernel symbols with addresses" \
        "grep -v '0000000000000000' /proc/kallsyms | head -n1 | grep -q '^[0-9a-f]'"
    
    # Test 3: Cannot load kernel modules
    test_escape_blocked "Cannot access /proc/modules for loading" \
        "insmod /tmp/test.ko 2>&1"
    
    # Test 4: Cannot read /proc/kmsg
    test_escape_blocked "Cannot read kernel messages" \
        "timeout 1 cat /proc/kmsg 2>&1"
    
    # Test 5: Cannot access /proc/config.gz
    test_escape_blocked "Cannot read kernel config" \
        "zcat /proc/config.gz 2>&1 | head -n1"
}

test_proc_self_exploitation() {
    log_section "/proc/self Exploitation Tests"
    
    # Test 1: Cannot write to /proc/self/mem
    test_escape_blocked "Cannot write to /proc/self/mem" \
        "dd if=/dev/zero of=/proc/self/mem bs=1 count=1 seek=0 2>&1"
    
    # Test 2: /proc/self/exe should not leak host paths
    test_functionality "/proc/self/exe points to container binary" \
        "readlink /proc/self/exe | grep -qv '^/usr/bin/sh\\|^/bin/sh\\|^/bin/bash'"
    
    # Test 3: Cannot exploit /proc/self/fd
    test_escape_blocked "Cannot exploit /proc/self/fd for escape" \
        "ls -la /proc/self/fd/0 2>&1 | grep -q '/dev/pts'"
    
    # Test 4: Cannot access parent process info
    test_escape_blocked "Cannot access /proc/self/../../* for parent info" \
        "cat /proc/self/../../cmdline 2>&1"
    
    # Test 5: Cannot modify /proc/self/attr
    test_escape_blocked "Cannot modify security attributes" \
        "echo 'unconfined' > /proc/self/attr/current 2>&1"
}

test_proc_host_visibility() {
    log_section "/proc Host Visibility Tests"
    
    # Test 1: Should not see many host processes
    test_functionality "Process list is isolated" \
        "[ \$(ls /proc | grep -c '^[0-9]\\+$') -lt 50 ]"
    
    # Test 2: Cannot access host process info
    test_escape_blocked "Cannot read host process cmdline" \
        "cat /proc/1/cmdline 2>&1 | grep -q 'systemd\\|init' && echo 'host visible'"
    
    # Test 3: Cannot access host process environment
    test_escape_blocked "Cannot read host process environment" \
        "cat /proc/1/environ 2>&1 | grep -q 'PATH'"
    
    # Test 4: Cannot access host process maps
    test_escape_blocked "Cannot read host process memory maps" \
        "cat /proc/1/maps 2>&1 | head -n1 | grep -q '^[0-9a-f]'"
    
    # Test 5: Cannot ptrace via /proc
    test_escape_blocked "Cannot access /proc/1/mem" \
        "dd if=/proc/1/mem of=/dev/null bs=1 count=1 2>&1"
}

test_sys_kernel_manipulation() {
    log_section "/sys/kernel Tests"
    
    # Test 1: Cannot modify kernel debug settings
    test_escape_blocked "Cannot modify /sys/kernel/debug" \
        "ls /sys/kernel/debug 2>&1 && echo test > /sys/kernel/debug/test 2>&1"
    
    # Test 2: Cannot load firmware
    test_escape_blocked "Cannot trigger firmware loading" \
        "echo 1 > /sys/class/firmware/test/loading 2>&1"
    
    # Test 3: Cannot modify module parameters
    test_escape_blocked "Cannot modify module parameters" \
        "echo 0 > /sys/module/kernel/parameters/panic 2>&1"
    
    # Test 4: Cannot access security features
    test_escape_blocked "Cannot disable secureboot" \
        "ls /sys/firmware/efi/efivars 2>&1 | grep -q 'SecureBoot'"
}

test_sys_class_manipulation() {
    log_section "/sys/class Tests"
    
    # Test 1: Cannot modify network settings
    test_escape_blocked "Cannot modify network via /sys" \
        "echo 0 > /sys/class/net/eth0/carrier 2>&1"
    
    # Test 2: Cannot modify block device settings
    test_escape_blocked "Cannot modify block device scheduler" \
        "echo deadline > /sys/block/sda/queue/scheduler 2>&1"
    
    # Test 3: Cannot modify graphics settings
    test_escape_blocked "Cannot modify graphics via /sys" \
        "echo 0 > /sys/class/graphics/fb0/blank 2>&1"
    
    # Test 4: Cannot unbind drivers
    test_escape_blocked "Cannot unbind drivers" \
        "echo '0000:00:00.0' > /sys/bus/pci/drivers/test/unbind 2>&1"
}

test_sys_devices_access() {
    log_section "/sys/devices Tests"
    
    # Test 1: Cannot modify device power state
    test_escape_blocked "Cannot modify device power state" \
        "echo on > /sys/devices/system/cpu/cpu0/online 2>&1"
    
    # Test 2: Cannot access CPU frequency settings
    test_escape_blocked "Cannot modify CPU frequency" \
        "echo performance > /sys/devices/system/cpu/cpu0/cpufreq/scaling_governor 2>&1"
    
    # Test 3: Cannot modify memory settings
    test_escape_blocked "Cannot modify memory online state" \
        "echo offline > /sys/devices/system/memory/memory0/state 2>&1"
}

test_proc_net_information() {
    log_section "/proc/net Information Tests"
    
    # Test 1: Network info should be isolated
    test_functionality "Network namespace is isolated" \
        "[ -f /proc/net/dev ]"
    
    # Test 2: Should not see host network connections
    test_escape_blocked "Cannot see extensive host connections" \
        "[ \$(cat /proc/net/tcp | wc -l) -lt 100 ]"
    
    # Test 3: Should not see host routes
    test_escape_blocked "Route table is isolated" \
        "ip route show | grep -qv 'default'"
}

test_proc_sys_fs() {
    log_section "/proc/sys/fs Tests"
    
    # Test 1: Cannot modify file-max
    test_escape_blocked "Cannot modify file-max" \
        "echo 999999999 > /proc/sys/fs/file-max 2>&1"
    
    # Test 2: Cannot modify inotify limits
    test_escape_blocked "Cannot modify inotify limits" \
        "echo 999999 > /proc/sys/fs/inotify/max_user_watches 2>&1"
    
    # Test 3: Cannot modify pipe limits
    test_escape_blocked "Cannot modify pipe-max-size" \
        "echo 999999999 > /proc/sys/fs/pipe-max-size 2>&1"
}

test_proc_sys_vm() {
    log_section "/proc/sys/vm Tests"
    
    # Test 1: Cannot modify overcommit settings
    test_escape_blocked "Cannot modify overcommit_memory" \
        "echo 1 > /proc/sys/vm/overcommit_memory 2>&1"
    
    # Test 2: Cannot modify swappiness
    test_escape_blocked "Cannot modify swappiness" \
        "echo 0 > /proc/sys/vm/swappiness 2>&1"
    
    # Test 3: Cannot drop caches
    test_escape_blocked "Cannot drop caches" \
        "echo 3 > /proc/sys/vm/drop_caches 2>&1"
}

test_proc_sys_net() {
    log_section "/proc/sys/net Tests"
    
    # Test 1: Cannot modify network forwarding
    test_escape_blocked "Cannot enable IP forwarding" \
        "echo 1 > /proc/sys/net/ipv4/ip_forward 2>&1"
    
    # Test 2: Cannot modify network security
    test_escape_blocked "Cannot disable RP filter" \
        "echo 0 > /proc/sys/net/ipv4/conf/all/rp_filter 2>&1"
    
    # Test 3: Cannot modify netfilter settings
    test_escape_blocked "Cannot modify netfilter" \
        "echo 0 > /proc/sys/net/netfilter/nf_conntrack_max 2>&1"
}

test_debugfs_access() {
    log_section "DebugFS Tests"
    
    # Test 1: Cannot access debugfs
    test_escape_blocked "Cannot mount debugfs" \
        "mount -t debugfs none /sys/kernel/debug 2>&1"
    
    # Test 2: Cannot read from existing debugfs
    test_escape_blocked "Cannot read debugfs entries" \
        "cat /sys/kernel/debug/sched_features 2>&1"
}

test_tracefs_access() {
    log_section "TraceFS Tests"
    
    # Test 1: Cannot access tracefs
    test_escape_blocked "Cannot mount tracefs" \
        "mount -t tracefs none /sys/kernel/tracing 2>&1"
    
    # Test 2: Cannot enable kernel tracing
    test_escape_blocked "Cannot enable tracing" \
        "echo 1 > /sys/kernel/tracing/tracing_on 2>&1"
}

# Run all procfs/sysfs tests
test_proc_sys_kernel
test_proc_special_files
test_proc_self_exploitation
test_proc_host_visibility
test_sys_kernel_manipulation
test_sys_class_manipulation
test_sys_devices_access
test_proc_net_information
test_proc_sys_fs
test_proc_sys_vm
test_proc_sys_net
test_debugfs_access
test_tracefs_access
