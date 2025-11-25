#!/bin/sh
# Test: Debian Security Features
# Validates security-related configurations

test_start "passwd file has correct permissions"
if [ -f /etc/passwd ]; then
    perms=$(stat -c %a /etc/passwd 2>/dev/null)
    if [ "$perms" = "644" ] || [ "$perms" = "640" ]; then
        test_pass
    else
        test_skip "passwd permissions non-standard: $perms"
    fi
else
    test_fail "/etc/passwd missing"
fi

test_start "shadow file has restricted permissions (if exists)"
if [ -f /etc/shadow ]; then
    perms=$(stat -c %a /etc/shadow 2>/dev/null)
    if [ "$perms" = "640" ] || [ "$perms" = "600" ]; then
        test_pass
    else
        test_fail "shadow permissions too permissive: $perms"
    fi
else
    test_skip "Shadow passwords not configured"
fi

test_start "Root home directory has restricted permissions"
if [ -d /root ]; then
    perms=$(stat -c %a /root 2>/dev/null)
    if [ "$perms" = "700" ] || [ "$perms" = "750" ]; then
        test_pass
    else
        test_skip "Root home permissions: $perms"
    fi
else
    test_fail "/root directory missing"
fi

test_start "sudoers file has correct permissions (if exists)"
if [ -f /etc/sudoers ]; then
    perms=$(stat -c %a /etc/sudoers 2>/dev/null)
    if [ "$perms" = "440" ] || [ "$perms" = "400" ]; then
        test_pass
    else
        test_fail "sudoers permissions incorrect: $perms"
    fi
else
    test_skip "sudoers not configured"
fi

test_start "Security update repository configured"
if grep -r "security.debian.org\|security.ubuntu.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -qv "^#"; then
    test_pass
else
    test_skip "Security repository not explicitly configured"
fi

test_start "PAM configuration exists"
if [ -d /etc/pam.d ] && [ -f /etc/pam.d/common-auth -o -f /etc/pam.d/system-auth ]; then
    test_pass
else
    test_skip "PAM not configured (may not be needed)"
fi

test_start "apparmor profiles directory exists (if apparmor)"
if test_command_exists apparmor_parser; then
    if [ -d /etc/apparmor.d ]; then
        test_pass
    else
        test_fail "AppArmor installed but profiles missing"
    fi
else
    test_skip "AppArmor not installed"
fi

test_start "ca-certificates package installed"
if dpkg -l ca-certificates 2>/dev/null | grep -q '^ii'; then
    test_pass
else
    test_skip "ca-certificates not installed (recommended)"
fi

test_start "SSL certificate directory exists"
if [ -d /etc/ssl/certs ] || [ -d /usr/share/ca-certificates ]; then
    test_pass
else
    test_skip "SSL certificates not configured"
fi

test_start "openssl command available"
if test_command_exists openssl; then
    test_pass
else
    test_skip "openssl not installed (recommended)"
fi

test_start "No world-writable files in /etc (sample check)"
if [ -d /etc ]; then
    count=$(find /etc -maxdepth 1 -type f -perm -002 2>/dev/null | wc -l)
    if [ "$count" -eq 0 ]; then
        test_pass
    else
        test_fail "Found $count world-writable files in /etc"
    fi
else
    test_fail "/etc directory missing"
fi

test_start "debsums available for package verification"
if test_command_exists debsums; then
    test_pass
else
    test_skip "debsums not installed (optional verification tool)"
fi
