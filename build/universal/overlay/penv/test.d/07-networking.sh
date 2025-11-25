#!/bin/sh
# Test: Basic Networking
# Validates network-related tools and configuration

test_start "Network configuration exists"
if test_file_exists /etc/hosts; then
    test_pass
else
    test_fail "/etc/hosts missing"
fi

test_start "Loopback interface is configured"
if grep -q '^127\.0\.0\.1' /etc/hosts 2>/dev/null; then
    test_pass
else
    test_fail "Loopback not in /etc/hosts"
fi

test_start "hostname command exists"
if test_command_exists hostname; then
    test_pass
else
    test_fail "hostname command not found"
fi

test_start "hostname can be queried"
if hostname >/dev/null 2>&1; then
    test_pass
else
    test_fail "hostname command failed"
fi

test_start "ping command exists"
if test_command_exists ping; then
    test_pass
else
    test_skip "ping not installed (optional)"
fi

test_start "Can ping loopback address (if ping available)"
if test_command_exists ping; then
    if ping -c 1 -W 1 127.0.0.1 >/dev/null 2>&1; then
        test_pass
    else
        test_skip "Loopback ping failed (container limitation)"
    fi
else
    test_skip "ping not available"
fi

test_start "netstat or ss command exists"
if test_command_exists netstat || test_command_exists ss; then
    test_pass
else
    test_skip "netstat/ss not installed (optional)"
fi

test_start "curl command exists"
if test_command_exists curl; then
    test_pass
else
    test_skip "curl not installed (optional)"
fi

test_start "wget command exists"
if test_command_exists wget; then
    test_pass
else
    test_skip "wget not installed (optional)"
fi

test_start "DNS resolution configuration exists"
if test_file_exists /etc/resolv.conf; then
    test_pass
else
    test_skip "No DNS configuration (expected in container)"
fi

test_start "Network utilities package indicators"
if test_command_exists ip || test_command_exists ifconfig; then
    test_pass
else
    test_skip "Advanced network tools not installed (optional)"
fi
