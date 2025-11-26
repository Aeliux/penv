#!/bin/sh
# Test: Debian Security Features
# Validates security-related configurations

test_start "Security update repository configured"
if grep -r "security.debian.org\|security.ubuntu.com" /etc/apt/sources.list /etc/apt/sources.list.d/ 2>/dev/null | grep -qv "^#"; then
    test_pass
else
    test_skip "Security repository not explicitly configured"
fi

test_start "ca-certificates package installed"
if dpkg -l ca-certificates 2>/dev/null | grep -q '^ii'; then
    test_pass
else
    test_skip "ca-certificates not installed (recommended)"
fi

test_start "debsums available for package verification"
if test_command_exists debsums; then
    test_pass
else
    test_skip "debsums not installed (optional verification tool)"
fi
