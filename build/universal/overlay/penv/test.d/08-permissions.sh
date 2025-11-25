#!/bin/sh
# Test: Permissions and Users
# Validates user/group and permission functionality

test_start "Running as root user"
if [ "$(id -u)" -eq 0 ]; then
    test_pass
else
    test_fail "Not running as root (UID=$(id -u))"
fi

test_start "Root user exists in /etc/passwd"
if grep -q '^root:x:0:0:' /etc/passwd 2>/dev/null; then
    test_pass
else
    test_fail "Root user not properly configured"
fi

test_start "Root group exists in /etc/group"
if grep -q '^root:x:0:' /etc/group 2>/dev/null; then
    test_pass
else
    test_fail "Root group not properly configured"
fi

test_start "whoami reports root"
if [ "$(whoami 2>/dev/null)" = "root" ]; then
    test_pass
else
    test_fail "whoami does not report root"
fi

test_start "id command reports UID 0"
if id -u >/dev/null 2>&1 && [ "$(id -u)" = "0" ]; then
    test_pass
else
    test_fail "id command failed or wrong UID"
fi

test_start "Can read root's home directory"
if [ -r /root ]; then
    test_pass
else
    test_fail "/root not readable"
fi

test_start "chmod command works"
if test_command_exists chmod; then
    test_pass
else
    test_fail "chmod command not found"
fi

test_start "chown command exists"
if test_command_exists chown; then
    test_pass
else
    test_fail "chown command not found"
fi

test_start "chgrp command exists"
if test_command_exists chgrp; then
    test_pass
else
    test_fail "chgrp command not found"
fi

test_start "su command exists"
if test_command_exists su; then
    test_pass
else
    test_skip "su not installed (optional)"
fi

test_start "sudo command exists"
if test_command_exists sudo; then
    test_pass
else
    test_skip "sudo not installed (optional)"
fi

test_start "umask is set"
if umask >/dev/null 2>&1; then
    test_pass
else
    test_fail "umask command failed"
fi

test_start "File permission bits work correctly"
TEST_FILE="/tmp/test-perms-$$"
if touch "$TEST_FILE" 2>/dev/null; then
    chmod 600 "$TEST_FILE" 2>/dev/null
    perms=$(stat -c %a "$TEST_FILE" 2>/dev/null)
    rm -f "$TEST_FILE"
    if [ "$perms" = "600" ]; then
        test_pass
    else
        test_fail "Permission bits not working (got $perms)"
    fi
else
    test_fail "Cannot create test file"
fi
