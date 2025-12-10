# Container Security Test Suite - Vulnerability Reference

This document describes all vulnerabilities tested by the suite, categorized by severity and type.

## Testing Modes

The test suite supports both **rootless** and **rooted** modes:

### Rootless Mode (Default)
```bash
./run-tests.sh /path/to/rootfs
```
- Tests container isolation without root privileges
- User namespace is utilized for isolation  
- Some tests may show different results (e.g., device access tests)
- Best for testing unprivileged container scenarios

### Root Mode
```bash
sudo ./run-tests.sh /path/to/rootfs
```
- Tests with full root privileges
- More comprehensive security testing
- Can test root-specific vulnerabilities
- Required for testing privileged container scenarios

**Important:** Both modes should be tested to ensure your implementation is secure in both privileged and unprivileged contexts.

## Test Categories Overview

### 1. Namespace Escape Vulnerabilities

**Critical Vulnerabilities:**
- **NS-001**: PID namespace breakout via /proc access
- **NS-002**: Mount namespace escape via shared mounts
- **NS-003**: User namespace UID/GID mapping exploitation
- **NS-004**: IPC namespace bypass for shared memory access
- **NS-005**: Network namespace escape to host network

**Why These Matter:**
- Namespace isolation is the foundation of container security
- Breaking namespace isolation allows container → host escape
- Can lead to full system compromise

### 2. Filesystem Escape Vulnerabilities

**Critical Vulnerabilities:**
- **FS-001**: Classic chroot escape via double chroot technique
- **FS-002**: Path traversal to host filesystem
- **FS-003**: Symlink exploitation to access host files
- **FS-004**: Mount manipulation to access host directories
- **FS-005**: /proc/self/root traversal escape
- **FS-006**: Pivot_root exploitation

**Why These Matter:**
- Allows reading/writing host filesystem from container
- Can steal credentials, modify system files, install backdoors
- Bypasses all container isolation guarantees

### 3. Privilege Escalation Vulnerabilities

**Critical Vulnerabilities:**
- **PE-001**: CAP_SYS_ADMIN abuse for system control
- **PE-002**: CAP_DAC_OVERRIDE for permission bypass
- **PE-003**: CAP_SYS_RAWIO for direct hardware access
- **PE-004**: CAP_SYS_MODULE for kernel module loading
- **PE-005**: Setuid binary exploitation
- **PE-006**: User namespace mapping to real root UID
- **PE-007**: NO_NEW_PRIVS bypass

**Why These Matter:**
- Elevates container processes to host root privileges
- Enables kernel exploitation and system takeover
- Bypasses security boundaries completely

### 4. Resource Isolation Vulnerabilities

**High Vulnerabilities:**
- **RI-001**: Cgroup escape/bypass
- **RI-002**: Memory exhaustion DoS
- **RI-003**: CPU exhaustion DoS
- **RI-004**: Fork bomb (PID exhaustion)
- **RI-005**: Disk space exhaustion
- **RI-006**: File descriptor exhaustion
- **RI-007**: IPC resource exhaustion

**Why These Matter:**
- Can crash or freeze host system
- Enables denial of service attacks
- Affects other containers on same host

### 5. Device Access Vulnerabilities

**Critical Vulnerabilities:**
- **DA-001**: Raw disk access (/dev/sda, /dev/nvme)
- **DA-002**: Kernel memory access (/dev/mem, /dev/kmem)
- **DA-003**: Device node creation for privileged devices
- **DA-004**: USB device access and manipulation
- **DA-005**: Graphics device access (DRI, framebuffer)
- **DA-006**: Input device access (keyboard/mouse sniffing)

**Why These Matter:**
- Direct disk access allows reading/modifying host filesystem
- Memory device access enables kernel exploitation
- Can compromise encryption, steal secrets, modify boot process

### 6. Procfs/Sysfs Exploitation Vulnerabilities

**Critical Vulnerabilities:**
- **PS-001**: /proc/kcore kernel memory read
- **PS-002**: /proc/kallsyms kernel address leak
- **PS-003**: /proc/sys kernel parameter modification
- **PS-004**: /proc/sysrq-trigger system control
- **PS-005**: /proc/self/mem process memory write
- **PS-006**: /sys/kernel/debug access
- **PS-007**: Kernel module loading via /sys

**Why These Matter:**
- Enables kernel exploitation and KASLR bypass
- Allows system crash or takeover
- Exposes kernel vulnerabilities to container

### 7. Network Isolation Vulnerabilities

**High Vulnerabilities:**
- **NI-001**: Network namespace escape to host network
- **NI-002**: Host network interface access
- **NI-003**: Raw packet socket creation
- **NI-004**: Iptables/netfilter manipulation
- **NI-005**: Privileged port binding on host
- **NI-006**: ARP poisoning attacks
- **NI-007**: Network sniffing (tcpdump/wireshark)

**Why These Matter:**
- Exposes host network traffic to container
- Enables man-in-the-middle attacks
- Can compromise other services on host network

### 8. OverlayFS Specific Vulnerabilities

**Critical Vulnerabilities:**
- **OF-001**: Upperdir path disclosure and access
- **OF-002**: Workdir access and manipulation
- **OF-003**: Whiteout file creation for layer manipulation
- **OF-004**: Overlay xattr manipulation (redirect, metacopy)
- **OF-005**: Copy-up race conditions
- **OF-006**: Layer crossing exploits
- **OF-007**: Overlay metadata file access

**Why These Matter:**
- OverlayFS is commonly used in containers
- Specific to container technology implementation
- Can bypass normal filesystem security

### 9. Information Disclosure Vulnerabilities

**Medium Vulnerabilities:**
- **ID-001**: Host hostname/domain disclosure
- **ID-002**: Host process listing visibility
- **ID-003**: Host filesystem structure enumeration
- **ID-004**: Kernel version and configuration exposure
- **ID-005**: Hardware information disclosure
- **ID-006**: Host network configuration leak
- **ID-007**: Host user account enumeration
- **ID-008**: Audit log access

**Why These Matter:**
- Aids in planning further attacks
- Reveals system architecture and defenses
- May expose sensitive business information

### 10. Exploitation Chain Vulnerabilities

**Critical Combinations:**
- **EC-001**: Namespace + Mount escape chains
- **EC-002**: Chroot + Capability combined exploits
- **EC-003**: Symlink + Mount race conditions
- **EC-004**: /proc exploitation chains
- **EC-005**: Device + Mount combined exploits
- **EC-006**: OverlayFS multi-stage exploits
- **EC-007**: Capability chaining attacks
- **EC-008**: Cgroup + Namespace combined escape
- **EC-009**: Setuid + Environment variable exploits
- **EC-010**: Multi-stage complex escape scenarios

**Why These Matter:**
- Real attacks often combine multiple vulnerabilities
- Single defenses may not stop combined attacks
- Tests defense-in-depth effectiveness

## Severity Ratings

### Critical
- Allows container → host escape
- Enables privilege escalation to host root
- Permits arbitrary host filesystem access
- **Action**: Must be fixed immediately

### High
- Enables denial of service on host
- Allows access to sensitive host information
- Can compromise host network security
- **Action**: Should be fixed urgently

### Medium
- Information disclosure that aids attacks
- Partial isolation bypass
- Resource abuse without full DoS
- **Action**: Should be addressed

### Low
- Minor information leaks
- Theoretical vulnerabilities
- Detection/fingerprinting issues
- **Action**: Fix when practical

## Known Container Runtime Vulnerabilities Tested

This test suite checks for many real-world CVEs and known container escapes:

### Historical Container Escapes
- **CVE-2016-1576**: OverlayFS setuid permission escalation
- **CVE-2019-5736**: runc container breakout
- **Dirty COW**: Memory corruption for privilege escalation
- **Shocker**: Docker container escape via /proc/self/exe
- **Felix Wilhelm's exploits**: Various capability-based escapes

### Namespace-Related CVEs
- User namespace UID mapping exploits
- PID namespace /proc access issues
- Mount namespace propagation problems

### Kernel Vulnerabilities
- KASLR bypass via kernel information leaks
- BPF privilege escalation
- Netfilter memory corruption

## Comparison with Other Containers

Use this test suite to compare rootbox with:

## References

- Linux Namespaces: `man 7 namespaces`
- Capabilities: `man 7 capabilities`
- OverlayFS: Linux kernel documentation
- Container security best practices: NIST SP 800-190
- Real-world exploits: NVD, exploit-db.com
