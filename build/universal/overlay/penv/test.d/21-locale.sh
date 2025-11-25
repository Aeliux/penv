#!/bin/sh
# Test: Locale and Internationalization (universal)
# Validates locale functionality across all Linux distributions

test_start "locale command exists"
if test_command_exists locale; then
    test_pass
else
    test_fail "locale command not found"
fi

test_start "locale command runs successfully"
if locale >/dev/null 2>&1; then
    test_pass
else
    test_fail "locale command failed"
fi

test_start "LANG environment variable is set"
if [ -n "$LANG" ]; then
    test_pass
else
    test_skip "LANG not set (using system default)"
fi

test_start "At least one locale is available"
if locale -a 2>/dev/null | grep -q '.'; then
    test_pass
else
    test_fail "No locales available"
fi

test_start "UTF-8 locale is available"
if locale -a 2>/dev/null | grep -qi 'utf.*8'; then
    test_pass
else
    test_skip "UTF-8 locale not configured"
fi

test_start "C locale is available"
if locale -a 2>/dev/null | grep -qE '^C$|^C\.'; then
    test_pass
else
    test_fail "C locale missing (required)"
fi

test_start "POSIX locale is available"
if locale -a 2>/dev/null | grep -q '^POSIX$'; then
    test_pass
else
    test_skip "POSIX locale not separately defined"
fi

test_start "Current locale is valid"
if locale -k LC_CTYPE >/dev/null 2>&1; then
    test_pass
else
    test_skip "Cannot validate current locale"
fi

test_start "Character encoding tools available"
if test_command_exists iconv; then
    test_pass
else
    test_skip "iconv not installed (optional)"
fi

test_start "LC_ALL can be set"
if (LC_ALL=C locale >/dev/null 2>&1); then
    test_pass
else
    test_fail "Cannot set LC_ALL"
fi

test_start "/usr/share/locale directory exists"
if test_dir_exists /usr/share/locale; then
    test_pass
else
    test_skip "Locale data not installed (optional)"
fi
