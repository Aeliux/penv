#!/bin/sh
# Test: Filesystem Structure
# Validates essential Linux filesystem hierarchy

# Essential directories that must exist
test_start "Root directory structure exists"
if test_dir_exists / && \
   test_dir_exists /bin && \
   test_dir_exists /etc && \
   test_dir_exists /usr && \
   test_dir_exists /var; then
    test_pass
else
    test_fail "Missing essential root directories"
fi

test_start "/tmp directory exists and is writable"
if test_dir_exists /tmp && [ -w /tmp ]; then
    test_pass
else
    test_fail "/tmp missing or not writable"
fi

test_start "/root home directory exists"
if test_dir_exists /root; then
    test_pass
else
    test_fail "/root directory missing"
fi

test_start "/usr/bin directory exists"
if test_dir_exists /usr/bin; then
    test_pass
else
    test_fail "/usr/bin directory missing"
fi

test_start "/usr/sbin directory exists"
if test_dir_exists /usr/sbin; then
    test_pass
else
    test_fail "/usr/sbin directory missing"
fi

test_start "/etc directory exists and is readable"
if test_dir_exists /etc && [ -r /etc ]; then
    test_pass
else
    test_fail "/etc missing or not readable"
fi

test_start "/var directory exists"
if test_dir_exists /var; then
    test_pass
else
    test_fail "/var directory missing"
fi

test_start "/var/log directory exists"
if test_dir_exists /var/log; then
    test_pass
else
    test_fail "/var/log directory missing"
fi

test_start "/var/tmp directory exists and is writable"
if test_dir_exists /var/tmp && [ -w /var/tmp ]; then
    test_pass
else
    test_fail "/var/tmp missing or not writable"
fi

test_start "/proc pseudo-filesystem is accessible"
if test_dir_exists /proc; then
    test_pass
else
    test_fail "/proc not accessible"
fi

test_start "/sys pseudo-filesystem is accessible"
if test_dir_exists /sys; then
    test_pass
else
    test_fail "/sys not accessible"
fi

test_start "/dev pseudo-filesystem is accessible"
if test_dir_exists /dev; then
    test_pass
else
    test_fail "/dev not accessible"
fi
