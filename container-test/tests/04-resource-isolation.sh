#!/bin/bash
# Resource Isolation Tests
# Tests for cgroup bypasses, resource exhaustion, and DoS attacks

test_cgroup_isolation() {
    log_section "Cgroup Isolation Tests"
    
    # Test 1: Should be in a cgroup
    test_functionality "Process is in a cgroup" \
        "[ -f /proc/self/cgroup ]"
    
    # Test 2: Cannot escape cgroup hierarchy
    test_escape_blocked "Cannot escape cgroup" \
        "echo \$\$ > /sys/fs/cgroup/cgroup.procs 2>&1"
    
    # Test 3: Cannot modify cgroup limits
    test_escape_blocked "Cannot modify cgroup memory limit" \
        "echo 9999999999 > /sys/fs/cgroup/memory/memory.limit_in_bytes 2>&1"
    
    # Test 4: Cannot create new cgroup
    test_escape_blocked "Cannot create new cgroup" \
        "mkdir /sys/fs/cgroup/memory/escape 2>&1"
    
    # Test 5: Cannot access parent cgroup
    test_escape_blocked "Cannot access parent cgroup" \
        "cat /sys/fs/cgroup/../../../cgroup.procs 2>&1"
}

test_memory_exhaustion() {
    log_section "Memory Exhaustion Tests"
    
    # Test 1: Memory bomb should be limited
    test_escape_blocked "Memory allocation bomb is contained" \
        "perl -e '\$a=\"A\"x10000000; while(1){\$a.=\$a}' 2>&1 & sleep 2; kill \$! 2>/dev/null"
    
    # Test 2: Cannot exhaust system memory
    test_escape_blocked "Cannot allocate unlimited memory" \
        "dd if=/dev/zero of=/dev/shm/bigfile bs=1G count=100 2>&1"
    
    # Test 3: Cannot use mmap to exhaust memory
    test_escape_blocked "mmap memory allocation is limited" \
        "python3 -c 'import mmap; mmap.mmap(-1, 1024*1024*1024*10)' 2>&1"
}

test_cpu_exhaustion() {
    log_section "CPU Exhaustion Tests"
    
    # Test 1: CPU bomb should be limited
    test_escape_blocked "CPU exhaustion attack is contained" \
        "timeout 3 sh -c 'while true; do :; done' 2>&1"
    
    # Test 2: Cannot spawn unlimited processes for CPU burn
    test_escape_blocked "Cannot spawn unlimited CPU burning processes" \
        "for i in \$(seq 1 1000); do (while true; do :; done) & done; sleep 2"
}

test_fork_bomb() {
    log_section "Fork Bomb Tests"
    
    # Test 1: Fork bomb should be limited by PID cgroup
    test_escape_blocked "Fork bomb is contained" \
        ":(){ :|:& };: 2>&1 & sleep 2; kill \$! 2>/dev/null"
    
    # Test 2: Cannot exceed process limit
    test_escape_blocked "Cannot exceed PID limit" \
        "for i in \$(seq 1 10000); do /bin/true & done 2>&1"
    
    # Test 3: ulimit should restrict processes
    test_functionality "Process limits are set" \
        "ulimit -u | grep -qv 'unlimited'"
}

test_disk_exhaustion() {
    log_section "Disk Exhaustion Tests"
    
    # Test 1: Cannot fill root filesystem
    test_escape_blocked "Cannot exhaust root filesystem" \
        "dd if=/dev/zero of=/bigfile bs=1G count=1000 2>&1"
    
    # Test 2: /tmp should have size limits
    test_escape_blocked "Cannot exhaust /tmp" \
        "dd if=/dev/zero of=/tmp/bigfile bs=1G count=100 2>&1"
    
    # Test 3: Cannot create unlimited inodes
    test_escape_blocked "Cannot create unlimited files" \
        "for i in \$(seq 1 1000000); do touch /tmp/file\$i 2>&1 || break; done; [ \$i -lt 1000000 ]"
}

test_file_descriptor_exhaustion() {
    log_section "File Descriptor Exhaustion Tests"
    
    # Test 1: File descriptor limit should be enforced
    test_functionality "File descriptor limit is set" \
        "ulimit -n | grep -qv 'unlimited'"
    
    # Test 2: Cannot open unlimited files
    test_escape_blocked "Cannot open unlimited file descriptors" \
        "for i in \$(seq 1 100000); do exec 3<>/tmp/test\$i 2>&1 || break; done; [ \$i -lt 100000 ]"
    
    # Test 3: Cannot exhaust system file descriptors
    test_escape_blocked "System file descriptor table protected" \
        "cat /proc/sys/fs/file-max 2>&1 && echo 'reading max, not exhausting'"
}

test_network_exhaustion() {
    log_section "Network Exhaustion Tests"
    
    # Test 1: Cannot open unlimited sockets
    test_escape_blocked "Cannot create unlimited sockets" \
        "for i in \$(seq 1 100000); do nc -l 900\$i 2>&1 & done; sleep 1"
    
    # Test 2: Cannot flood network
    test_escape_blocked "Cannot perform network flood" \
        "ping -f 127.0.0.1 2>&1 & sleep 2; kill \$! 2>/dev/null"
}

test_ipc_exhaustion() {
    log_section "IPC Resource Exhaustion Tests"
    
    # Test 1: Cannot create unlimited message queues
    test_escape_blocked "Message queue limit enforced" \
        "for i in \$(seq 1 10000); do ipcmk -Q 2>&1 || break; done; [ \$i -lt 10000 ]"
    
    # Test 2: Cannot create unlimited semaphores
    test_escape_blocked "Semaphore limit enforced" \
        "for i in \$(seq 1 10000); do ipcmk -S 1 2>&1 || break; done; [ \$i -lt 10000 ]"
    
    # Test 3: Cannot create unlimited shared memory
    test_escape_blocked "Shared memory limit enforced" \
        "for i in \$(seq 1 10000); do ipcmk -M 1024 2>&1 || break; done; [ \$i -lt 10000 ]"
}

test_kernel_resource_limits() {
    log_section "Kernel Resource Limit Tests"
    
    # Test 1: Cannot modify kernel resource limits
    test_escape_blocked "Cannot increase kernel limits" \
        "echo 999999 > /proc/sys/kernel/pid_max 2>&1"
    
    # Test 2: Cannot modify file limits
    test_escape_blocked "Cannot modify file-max" \
        "echo 9999999 > /proc/sys/fs/file-max 2>&1"
    
    # Test 3: Cannot disable resource limits
    test_escape_blocked "Cannot disable OOM killer protection" \
        "echo -17 > /proc/self/oom_adj 2>&1"
}

test_time_based_attacks() {
    log_section "Time-based Resource Tests"
    
    # Test 1: Cannot consume clock time
    test_escape_blocked "CPU time limits should be enforced" \
        "ulimit -t 10 && timeout 15 sh -c 'while true; do :; done' 2>&1"
    
    # Test 2: Cannot sleep indefinitely
    test_escape_blocked "Cannot create blocking sleep processes" \
        "for i in \$(seq 1 1000); do sleep 86400 & done; sleep 2; jobs | wc -l | grep -q '^[0-9]$'"
}

test_cgroup_v2_features() {
    log_section "Cgroup v2 Tests"
    
    # Test 1: Check cgroup version
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        test_functionality "Cgroup v2 may be available" \
            "cat /sys/fs/cgroup/cgroup.controllers 2>&1 | grep -q '.'"
        
        # Test 2: Cannot escape cgroup v2
        test_escape_blocked "Cannot escape cgroup v2 hierarchy" \
            "echo \$\$ > /sys/fs/cgroup/cgroup.procs 2>&1"
    else
        log_skip "Cgroup v2 not available, skipping v2-specific tests"
    fi
}

# Run all resource isolation tests
test_cgroup_isolation
test_memory_exhaustion
test_cpu_exhaustion
test_fork_bomb
test_disk_exhaustion
test_file_descriptor_exhaustion
test_network_exhaustion
test_ipc_exhaustion
test_kernel_resource_limits
test_time_based_attacks
test_cgroup_v2_features
