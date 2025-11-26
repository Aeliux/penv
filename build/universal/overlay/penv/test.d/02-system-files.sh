#!/bin/sh
# Test: Essential System Files
# Validates presence of critical system configuration files

test_start "/etc/passwd exists and is readable"
if test_file_exists /etc/passwd && [ -r /etc/passwd ]; then
    test_pass
else
    test_fail "/etc/passwd missing or not readable"
fi

test_start "/etc/group exists and is readable"
if test_file_exists /etc/group && [ -r /etc/group ]; then
    test_pass
else
    test_fail "/etc/group missing or not readable"
fi

test_start "/etc/passwd contains root user"
if test_file_exists /etc/passwd && grep -q '^root:' /etc/passwd; then
    test_pass
else
    test_fail "root user not found in /etc/passwd"
fi

test_start "/etc/group contains root group"
if test_file_exists /etc/group && grep -q '^root:' /etc/group; then
    test_pass
else
    test_fail "root group not found in /etc/group"
fi

test_start "/etc/shadow exists (if present, is restricted)"
if test_file_exists /etc/shadow; then
    if [ ! -r /etc/shadow ] || [ "$(stat -c %a /etc/shadow 2>/dev/null)" = "640" ] || [ "$(stat -c %a /etc/shadow 2>/dev/null)" = "600" ]; then
        test_pass
    else
        test_fail "/etc/shadow has incorrect permissions"
    fi
else
    test_skip "Shadow passwords not in use"
fi

test_start "/etc/hostname or /etc/HOSTNAME exists"
if test_file_exists /etc/hostname || test_file_exists /etc/HOSTNAME; then
    test_pass
else
    test_fail "No hostname configuration file"
fi

test_start "/etc/hosts exists and is readable"
if test_file_exists /etc/hosts && [ -r /etc/hosts ]; then
    test_pass
else
    test_fail "/etc/hosts missing or not readable"
fi

test_start "/etc/hosts contains localhost entry"
if test_file_exists /etc/hosts && grep -q '127.0.0.1.*localhost' /etc/hosts; then
    test_pass
else
    test_fail "localhost not configured in /etc/hosts"
fi

test_start "/etc/resolv.conf exists (DNS configuration)"
if test_file_exists /etc/resolv.conf; then
    test_pass
else
    test_skip "No DNS configuration (expected in container)"
fi

test_start "/etc/nsswitch.conf exists"
if test_file_exists /etc/nsswitch.conf && [ -r /etc/nsswitch.conf ]; then
    test_pass
else
    test_fail "/etc/nsswitch.conf missing or not readable"
fi

test_start "/etc/profile exists for shell initialization"
if test_file_exists /etc/profile; then
    test_pass
else
    test_skip "No /etc/profile (optional)"
fi

test_start "/etc/os-release exists"
if test_file_exists /etc/os-release; then
    test_pass
else
    test_fail "/etc/os-release missing"
fi
