#!/bin/sh
# Test: Debian-Specific Library Configuration
# Validates Debian-specific library management (multi-arch, etc.)

# Only run on Debian systems
if [ "$PENV_METADATA_FAMILY" != "debian" ] && [ "$PENV_METADATA_DISTRO" != "debian" ]; then
    test_skip "Not a Debian-based system"
    exit 0
fi

test_start "Multi-arch support directory structure"
if test_dir_exists /usr/lib/x86_64-linux-gnu || \
   test_dir_exists /usr/lib/aarch64-linux-gnu || \
   test_dir_exists /usr/lib/arm-linux-gnueabihf || \
   test_dir_exists /usr/lib/i386-linux-gnu; then
    test_pass
else
    test_skip "Multi-arch directories not present (older Debian)"
fi

test_start "Debian uses GNU libc (GLIBC)"
if [ -f /lib/*/libc.so.6 ] || [ -f /lib64/libc.so.6 ] || [ -f /usr/lib/*/libc.so.6 ]; then
    test_pass
else
    test_fail "GLIBC libc.so.6 not found"
fi

test_start "Debian-specific linker naming (ld-linux)"
if [ -f /lib/*/ld-linux*.so.* ] || [ -f /lib64/ld-linux*.so.* ] || [ -f /lib/ld-linux*.so.* ]; then
    test_pass
else
    test_fail "Debian ld-linux not found"
fi

test_start "Shared library loader configuration directory exists"
if test_dir_exists /etc/ld.so.conf.d; then
    test_pass
else
    test_skip "/etc/ld.so.conf.d not present (unusual for Debian)"
fi

test_start "ldconfig is available (Debian standard)"
if test_command_exists ldconfig; then
    test_pass
else
    test_fail "ldconfig not found (required for Debian)"
fi
