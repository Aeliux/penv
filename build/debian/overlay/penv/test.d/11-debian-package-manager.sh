#!/bin/sh
# Test: Debian Package Manager (dpkg/APT)
# Validates package management system functionality

test_start "dpkg command exists"
if test_command_exists dpkg; then
    test_pass
else
    test_fail "dpkg not found"
fi

test_start "dpkg can query package list"
if dpkg -l >/dev/null 2>&1; then
    test_pass
else
    test_fail "dpkg -l failed"
fi

test_start "dpkg database exists"
if test_dir_exists /var/lib/dpkg && test_file_exists /var/lib/dpkg/status; then
    test_pass
else
    test_fail "dpkg database missing"
fi

test_start "apt-get command exists"
if test_command_exists apt-get; then
    test_pass
else
    test_fail "apt-get not found"
fi

test_start "apt command exists"
if test_command_exists apt; then
    test_pass
else
    test_skip "apt not installed (older Debian)"
fi

test_start "/etc/apt directory exists"
if test_dir_exists /etc/apt; then
    test_pass
else
    test_fail "/etc/apt directory missing"
fi

test_start "/etc/apt/sources.list exists or sources.list.d has entries"
if test_file_exists /etc/apt/sources.list || [ -n "$(ls -A /etc/apt/sources.list.d 2>/dev/null)" ]; then
    test_pass
else
    test_fail "No APT sources configured"
fi

test_start "APT sources list is readable"
if [ -r /etc/apt/sources.list ] || test_dir_exists /etc/apt/sources.list.d; then
    test_pass
else
    test_fail "Cannot read APT sources"
fi

test_start "/var/lib/apt directory exists"
if test_dir_exists /var/lib/apt; then
    test_pass
else
    test_fail "/var/lib/apt missing"
fi

test_start "/var/cache/apt directory is small"
if test_dir_exists /var/cache/apt; then
    cache_size=$(du -s /var/cache/apt 2>/dev/null | cut -f1)
    if [ "$cache_size" -lt 1048576 ]; then
        test_pass
    else
        test_fail "/var/cache/apt size is too large"
    fi
else
    test_pass
fi

test_start "dpkg-query command works"
if test_command_exists dpkg-query && dpkg-query -W -f='${Package}\n' dpkg >/dev/null 2>&1; then
    test_pass
else
    test_fail "dpkg-query failed"
fi

test_start "apt-cache command exists"
if test_command_exists apt-cache; then
    test_pass
else
    test_skip "apt-cache not available"
fi

test_start "Essential packages are installed"
essential_ok=true
for pkg in base-files base-passwd; do
    if ! dpkg -l "$pkg" >/dev/null 2>&1; then
        essential_ok=false
        break
    fi
done
if $essential_ok; then
    test_pass
else
    test_fail "Essential packages missing"
fi

test_start "dpkg architecture is set"
if dpkg --print-architecture >/dev/null 2>&1; then
    test_pass
else
    test_fail "dpkg architecture not configured"
fi

test_start "APT configuration directory exists"
if test_dir_exists /etc/apt/apt.conf.d; then
    test_pass
else
    test_fail "/etc/apt/apt.conf.d missing"
fi
