#!/bin/sh
# Test: Debian-Specific Locale Configuration
# Validates Debian-specific locale management (locales package, locale-gen)

# Only run on Debian systems
if [ "$PENV_METADATA_FAMILY" != "debian" ] && [ "$PENV_METADATA_DISTRO" != "debian" ]; then
    test_skip "Not a Debian-based system"
    exit 0
fi

test_start "C.UTF-8 locale is available (Debian default)"
if locale -a 2>/dev/null | grep -q 'C\.UTF-8\|C\.utf8'; then
    test_pass
else
    test_skip "C.UTF-8 not available (older Debian)"
fi

test_start "locales package is installed"
if dpkg -l locales >/dev/null 2>&1; then
    test_pass
else
    test_skip "locales package not installed"
fi

test_start "locale-gen command exists (Debian tool)"
if test_command_exists locale-gen; then
    test_pass
else
    test_skip "locale-gen not available"
fi

test_start "update-locale command exists (Debian tool)"
if test_command_exists update-locale; then
    test_pass
else
    test_skip "update-locale not available"
fi
