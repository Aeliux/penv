#!/bin/sh
# Test: Debian Base System
# Validates Debian-specific base system functionality

# Check if this is a Debian-based system
test_start "Debian distribution detected"
if [ "$PENV_METADATA_FAMILY" = "debian" ] || [ "$PENV_METADATA_DISTRO" = "debian" ]; then
    test_pass
    IS_DEBIAN=1
else
    test_skip "Not a Debian-based system"
    IS_DEBIAN=0
fi

# Only run remaining tests if this is Debian
if [ "$IS_DEBIAN" -eq 1 ]; then

test_start "/etc/debian_version exists"
if test_file_exists /etc/debian_version; then
    test_pass
else
    test_fail "/etc/debian_version missing"
fi

test_start "Debian version is readable"
if [ -r /etc/debian_version ] && [ -s /etc/debian_version ]; then
    test_pass
else
    test_fail "Cannot read Debian version"
fi

test_start "/etc/os-release exists"
if test_file_exists /etc/os-release; then
    test_pass
else
    test_fail "/etc/os-release missing"
fi

test_start "/etc/os-release identifies Debian"
if grep -qi 'debian' /etc/os-release 2>/dev/null; then
    test_pass
else
    test_fail "/etc/os-release does not identify Debian"
fi

test_start "lsb_release command exists"
if test_command_exists lsb_release; then
    test_pass
else
    test_skip "lsb_release not installed (optional)"
fi

test_start "Debian archive keyring exists"
if test_dir_exists /etc/apt/trusted.gpg.d || test_file_exists /etc/apt/trusted.gpg; then
    test_pass
else
    test_fail "APT keyring missing"
fi

test_start "Debian base-files package installed"
if dpkg -l base-files >/dev/null 2>&1; then
    test_pass
else
    test_fail "base-files package not installed"
fi

test_start "/usr/share/doc directory exists"
if test_dir_exists /usr/share/doc; then
    test_pass
else
    test_fail "/usr/share/doc missing"
fi

test_start "/usr/share/man directory exists"
if test_dir_exists /usr/share/man; then
    test_pass
else
    test_skip "Man pages not installed (optional)"
fi

test_start "Debian alternatives system exists"
if test_command_exists update-alternatives; then
    test_pass
else
    test_skip "update-alternatives not available"
fi

fi # End of Debian-specific tests
