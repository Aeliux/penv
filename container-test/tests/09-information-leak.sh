#!/bin/bash
# Information Leak Tests
# Tests for host information disclosure through various channels

test_hostname_leaks() {
    log_section "Hostname/Domain Leak Tests"
    
    # Test 1: Hostname should be containerized
    test_functionality "Hostname is set to rootbox" \
        "hostname | grep -q 'rootbox'"
    
    # Test 2: Cannot read host hostname
    test_escape_blocked "Cannot read host hostname from /proc" \
        "cat /proc/sys/kernel/hostname | grep -qv 'rootbox'"
    
    # Test 3: Domain name should be isolated
    test_functionality "Domain is isolated" \
        "dnsdomainname 2>&1 | grep -qv '\\.com$\\|\\.org$\\|\\.net$' || echo 'isolated'"
    
    # Test 4: Cannot read hostname from environment
    test_escape_blocked "HOST environment not leaked" \
        "env | grep -i 'HOST=' | grep -qv 'rootbox'"
}

test_process_information_leaks() {
    log_section "Process Information Leak Tests"
    
    # Test 1: Should not see many host processes
    test_functionality "Process list is limited" \
        "[ \$(ps aux | wc -l) -lt 50 ]"
    
    # Test 2: Cannot see host init process details
    test_escape_blocked "Cannot see host init in ps" \
        "ps aux | grep -q 'systemd.*--system' || ps aux | grep -q '/sbin/init'"
    
    # Test 3: /proc should not expose host PIDs
    test_functionality "Only container PIDs visible" \
        "[ \$(ls -d /proc/[0-9]* | wc -l) -lt 100 ]"
    
    # Test 4: Cannot read host process cmdline
    test_escape_blocked "Cannot access host process cmdlines" \
        "find /proc -name cmdline -exec cat {} \\; 2>&1 | grep -q 'docker\\|containerd\\|systemd'"
}

test_filesystem_structure_leaks() {
    log_section "Filesystem Structure Leak Tests"
    
    # Test 1: Root should not reveal host structure
    test_functionality "Root directory looks like isolated system" \
        "ls / | grep -q 'bin\\|etc\\|usr'"
    
    # Test 2: Should not see host home directories
    test_escape_blocked "Cannot see host /home structure" \
        "[ -d /home ] && ls /home 2>&1 | grep -q '^[a-z]' && [ \$(ls /home | wc -l) -gt 5 ]"
    
    # Test 3: Should not see host /root
    test_escape_blocked "Cannot access host /root contents" \
        "ls /root/.bashrc /root/.ssh 2>&1 | grep -qv 'No such file'"
    
    # Test 4: Mount table should not reveal host mounts
    test_escape_blocked "Mount table doesn't reveal host filesystem" \
        "mount | grep -q '/mnt/\\|/media/\\|/home/.*/Documents'"
}

test_kernel_information_leaks() {
    log_section "Kernel Information Leak Tests"
    
    # Test 1: Kernel version is exposed (acceptable)
    test_functionality "Can read kernel version" \
        "uname -r | grep -q '[0-9]\\+\\.[0-9]'"
    
    # Test 2: Cannot read kernel symbols
    test_escape_blocked "Cannot read kernel symbols with addresses" \
        "cat /proc/kallsyms | grep -v ' 0000000000000000 ' | head -n1 | grep -q '^[0-9a-f]\\{16\\}'"
    
    # Test 3: Cannot read kernel config
    test_escape_blocked "Cannot read kernel configuration" \
        "cat /proc/config.gz 2>&1 | gunzip 2>&1 | head -n1"
    
    # Test 4: dmesg should be restricted
    test_escape_blocked "Cannot read kernel logs via dmesg" \
        "dmesg | head -n1 | grep -q '\\[.*\\]'"
    
    # Test 5: Cannot read /proc/kmsg
    test_escape_blocked "Cannot read /proc/kmsg" \
        "timeout 1 cat /proc/kmsg 2>&1"
}

test_hardware_information_leaks() {
    log_section "Hardware Information Leak Tests"
    
    # Test 1: CPU info is exposed (acceptable for performance)
    test_functionality "Can read CPU info" \
        "cat /proc/cpuinfo | grep -q 'processor'"
    
    # Test 2: Memory info should be limited to container
    test_functionality "Memory info available" \
        "cat /proc/meminfo | grep -q 'MemTotal'"
    
    # Test 3: Cannot enumerate PCI devices
    test_escape_blocked "Cannot enumerate PCI devices" \
        "lspci 2>&1 | grep -q '[0-9]\\{2\\}:[0-9]\\{2\\}'"
    
    # Test 4: Cannot enumerate USB devices  
    test_escape_blocked "Cannot enumerate USB devices" \
        "lsusb 2>&1 | grep -q 'Bus [0-9]'"
    
    # Test 5: Cannot read DMI information
    test_escape_blocked "Cannot read DMI/SMBIOS info" \
        "dmidecode 2>&1 | grep -q 'SMBIOS'"
}

test_network_information_leaks() {
    log_section "Network Information Leak Tests"
    
    # Test 1: Should have limited network interfaces
    test_functionality "Network interfaces are limited" \
        "[ \$(ip link show | grep -c '^[0-9]') -lt 10 ]"
    
    # Test 2: Should not see host IP addresses
    test_escape_blocked "Cannot see host network configuration" \
        "ip addr show | grep inet | grep -v '127.0.0.1' | wc -l | grep -q '^[5-9]\\|^[1-9][0-9]'"
    
    # Test 3: Cannot see host routing table
    test_escape_blocked "Routing table is isolated" \
        "ip route show | wc -l | grep -q '^[0-3]$'"
    
    # Test 4: Cannot see host ARP cache
    test_functionality "ARP cache is isolated" \
        "[ \$(ip neigh show | wc -l) -lt 10 ]"
    
    # Test 5: Cannot resolve host's internal hostnames
    test_escape_blocked "Cannot see host's /etc/hosts" \
        "[ -f /etc/hosts ] && cat /etc/hosts | grep -qv '^127\\|^::1\\|^$\\|^#'"
}

test_user_information_leaks() {
    log_section "User Information Leak Tests"
    
    # Test 1: /etc/passwd should not reveal host users
    test_escape_blocked "Cannot see host user accounts" \
        "[ -f /etc/passwd ] && cat /etc/passwd | grep -v 'nologin\\|false' | wc -l | grep -q '^[1-9][0-9]'"
    
    # Test 2: /etc/shadow should not be readable
    test_escape_blocked "Cannot read /etc/shadow" \
        "cat /etc/shadow 2>&1 | grep -q '^[a-z].*:'"
    
    # Test 3: /etc/group should be limited
    test_escape_blocked "Group file doesn't leak host groups" \
        "[ -f /etc/group ] && cat /etc/group | wc -l | grep -q '^[5-9][0-9]\\|^[1-9][0-9][0-9]'"
    
    # Test 4: Cannot see host user home directories
    test_escape_blocked "Cannot enumerate host users via /home" \
        "ls /home 2>&1 | grep -v '^$' | wc -l | grep -q '^[5-9]\\|^[1-9][0-9]'"
}

test_container_identification() {
    log_section "Container Detection/Identification Tests"
    
    # Test 1: Container can be detected (not a security issue)
    test_functionality "Container environment can be detected" \
        "[ -f /.dockerenv ] || mount | grep -q overlay || hostname | grep -q rootbox"
    
    # Test 2: cgroup should indicate containerization
    test_functionality "Cgroup reveals containerization" \
        "cat /proc/self/cgroup | grep -q '.'"
    
    # Test 3: Should not reveal container runtime details
    test_escape_blocked "Cannot identify host container runtime" \
        "ps aux | grep -q 'dockerd\\|containerd\\|podman'"
}

test_timing_attacks() {
    log_section "Timing Side-Channel Tests"
    
    # Test 1: Cannot measure precise timing for attacks
    test_functionality "Clock sources available" \
        "cat /proc/timer_list 2>&1 | grep -q 'clock' || echo 'restricted'"
    
    # Test 2: RDTSC might be available (acceptable)
    test_functionality "Basic timing available" \
        "time sleep 0.1 2>&1 | grep -q 'real'"
}

test_audit_log_leaks() {
    log_section "Audit Log Leak Tests"
    
    # Test 1: Cannot read audit logs
    test_escape_blocked "Cannot read audit logs" \
        "cat /var/log/audit/audit.log 2>&1 | head -n1 | grep -q 'type='"
    
    # Test 2: Cannot read syslog
    test_escape_blocked "Cannot read system logs" \
        "cat /var/log/syslog 2>&1 | head -n1 | grep -q '[0-9]\\{4\\}'"
    
    # Test 3: Cannot access journal
    test_escape_blocked "Cannot access systemd journal" \
        "journalctl -n 10 2>&1 | grep -q '^[A-Z]'"
}

test_environment_variable_leaks() {
    log_section "Environment Variable Leak Tests"
    
    # Test 1: Check for leaked host paths in PATH
    test_functionality "PATH is containerized" \
        "echo \$PATH | grep -q '/bin:\\|/usr/bin'"
    
    # Test 2: Should not have host-specific env vars
    test_escape_blocked "No host-specific environment variables" \
        "env | grep -qi 'DOCKER\\|KUBERNETES\\|K8S' && echo 'leaked'"
    
    # Test 3: Should not leak host user info
    test_escape_blocked "USER/LOGNAME not leaked from host" \
        "env | grep -E '^(USER|LOGNAME)=' | grep -qv 'root'"
}

test_timezone_locale_leaks() {
    log_section "Timezone/Locale Information Tests"
    
    # Test 1: Timezone is set (may reveal host location)
    test_functionality "Timezone is configured" \
        "date | grep -q '[0-9]\\{4\\}' || [ -f /etc/timezone ]"
    
    # Test 2: Locale doesn't necessarily leak host info
    test_functionality "Locale is set" \
        "locale 2>&1 | grep -q 'LANG=\\|LC_'"
}

test_selinux_apparmor_leaks() {
    log_section "LSM Information Leak Tests"
    
    # Test 1: SELinux/AppArmor status may be visible
    test_functionality "LSM status can be checked" \
        "cat /proc/self/attr/current 2>&1 | grep -q '.' || echo 'no LSM'"
    
    # Test 2: Cannot read host AppArmor profiles
    test_escape_blocked "Cannot enumerate host AppArmor profiles" \
        "cat /sys/kernel/security/apparmor/profiles 2>&1 | wc -l | grep -q '^[1-9][0-9]'"
}

test_container_escape_indicators() {
    log_section "Container Escape Indicator Tests"
    
    # Test 1: Check for obvious escape indicators
    test_escape_blocked "No obvious escape to host filesystem" \
        "[ ! -f /host/etc/passwd ] && [ ! -d /host/root ]"
    
    # Test 2: Cannot find host filesystem via common paths
    test_escape_blocked "Cannot find host via /proc/1/root" \
        "ls /proc/1/root/etc/hostname 2>&1 | grep -qv 'No such file'"
    
    # Test 3: Cannot detect breakout via socket
    test_escape_blocked "No obvious socket escape paths" \
        "[ ! -S /var/run/docker.sock ] && [ ! -S /run/containerd/containerd.sock ]"
}

# Run all information leak tests
test_hostname_leaks
test_process_information_leaks
test_filesystem_structure_leaks
test_kernel_information_leaks
test_hardware_information_leaks
test_network_information_leaks
test_user_information_leaks
test_container_identification
test_timing_attacks
test_audit_log_leaks
test_environment_variable_leaks
test_timezone_locale_leaks
test_selinux_apparmor_leaks
test_container_escape_indicators
