#!/bin/sh
# Test: Core Utilities
# Validates essential Unix/Linux commands

# File operations
test_start "ls command exists"
if test_command_exists ls; then
    test_pass
else
    test_fail "ls command not found"
fi

test_start "ls can list directory contents"
if ls / >/dev/null 2>&1; then
    test_pass
else
    test_fail "ls execution failed"
fi

test_start "cat command exists"
if test_command_exists cat; then
    test_pass
else
    test_fail "cat command not found"
fi

test_start "cat can read files"
if echo "test" | cat >/dev/null 2>&1; then
    test_pass
else
    test_fail "cat execution failed"
fi

test_start "cp command exists"
if test_command_exists cp; then
    test_pass
else
    test_fail "cp command not found"
fi

test_start "mv command exists"
if test_command_exists mv; then
    test_pass
else
    test_fail "mv command not found"
fi

test_start "rm command exists"
if test_command_exists rm; then
    test_pass
else
    test_fail "rm command not found"
fi

test_start "mkdir command exists"
if test_command_exists mkdir; then
    test_pass
else
    test_fail "mkdir command not found"
fi

test_start "rmdir command exists"
if test_command_exists rmdir; then
    test_pass
else
    test_fail "rmdir command not found"
fi

test_start "touch command exists"
if test_command_exists touch; then
    test_pass
else
    test_fail "touch command not found"
fi

# Text processing
test_start "grep command exists"
if test_command_exists grep; then
    test_pass
else
    test_fail "grep command not found"
fi

test_start "grep can search text"
if echo "test" | grep -q "test" 2>/dev/null; then
    test_pass
else
    test_fail "grep execution failed"
fi

test_start "sed command exists"
if test_command_exists sed; then
    test_pass
else
    test_fail "sed command not found"
fi

test_start "awk command exists"
if test_command_exists awk; then
    test_pass
else
    test_fail "awk command not found"
fi

test_start "find command exists"
if test_command_exists find; then
    test_pass
else
    test_fail "find command not found"
fi

test_start "find can search directories"
if find / -maxdepth 1 -name "etc" >/dev/null 2>&1; then
    test_pass
else
    test_fail "find execution failed"
fi

# System information
test_start "uname command exists"
if test_command_exists uname; then
    test_pass
else
    test_fail "uname command not found"
fi

test_start "uname can display system information"
if uname -a >/dev/null 2>&1; then
    test_pass
else
    test_fail "uname execution failed"
fi

test_start "whoami command exists"
if test_command_exists whoami; then
    test_pass
else
    test_fail "whoami command not found"
fi

test_start "id command exists"
if test_command_exists id; then
    test_pass
else
    test_fail "id command not found"
fi

test_start "pwd command exists"
if test_command_exists pwd; then
    test_pass
else
    test_fail "pwd command not found"
fi

test_start "pwd can show current directory"
if pwd >/dev/null 2>&1; then
    test_pass
else
    test_fail "pwd execution failed"
fi

test_start "echo command works"
if output=$(echo "test" 2>&1) && [ "$output" = "test" ]; then
    test_pass
else
    test_fail "echo command failed"
fi

test_start "date command exists"
if test_command_exists date; then
    test_pass
else
    test_fail "date command not found"
fi
