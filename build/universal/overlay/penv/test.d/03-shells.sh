#!/bin/sh
# Test: Shell Availability and Functionality
# Validates shell interpreters and basic shell operations

test_start "POSIX shell (/bin/sh) exists"
if test_file_exists /bin/sh; then
    test_pass
else
    test_fail "/bin/sh not found"
fi

test_start "/bin/sh is executable"
if test_executable /bin/sh; then
    test_pass
else
    test_fail "/bin/sh not executable"
fi

test_start "Shell can execute simple commands"
if output=$(/bin/sh -c 'echo test' 2>&1) && [ "$output" = "test" ]; then
    test_pass
else
    test_fail "Shell command execution failed"
fi

test_start "Shell supports variable assignment"
if /bin/sh -c 'TEST_VAR=value; [ "$TEST_VAR" = "value" ]' 2>/dev/null; then
    test_pass
else
    test_fail "Variable assignment failed"
fi

test_start "Shell supports command substitution"
if /bin/sh -c 'result=$(echo test); [ "$result" = "test" ]' 2>/dev/null; then
    test_pass
else
    test_fail "Command substitution failed"
fi

test_start "Shell supports conditionals"
if /bin/sh -c 'if [ 1 -eq 1 ]; then exit 0; else exit 1; fi' 2>/dev/null; then
    test_pass
else
    test_fail "Conditional execution failed"
fi

test_start "Shell supports loops"
if /bin/sh -c 'for i in 1 2 3; do : ; done' 2>/dev/null; then
    test_pass
else
    test_fail "Loop execution failed"
fi

test_start "Bash shell exists"
if test_command_exists bash; then
    test_pass
else
    test_fail "Bash not installed"
fi

test_start "Bash can execute commands"
if bash -c 'echo test' >/dev/null 2>&1; then
    test_pass
else
    test_fail "Bash execution failed"
fi

test_start "/etc/shells exists and lists available shells"
if test_file_exists /etc/shells && [ -s /etc/shells ]; then
    test_pass
else
    test_skip "/etc/shells not present (optional)"
fi

test_start "Interactive shell reads profile"
if test_file_exists /etc/profile || test_file_exists /root/.profile; then
    test_pass
else
    test_skip "No profile files (optional)"
fi
