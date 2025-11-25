#!/bin/sh
# Test: Process Management
# Validates process-related functionality

test_start "ps command exists"
if test_command_exists ps; then
    test_pass
else
    test_fail "ps command not found"
fi

test_start "ps can list processes"
if ps >/dev/null 2>&1; then
    test_pass
else
    test_fail "ps execution failed"
fi

test_start "ps shows current shell process"
if ps -p $$ >/dev/null 2>&1; then
    test_pass
else
    test_fail "Cannot find current process"
fi

test_start "Can spawn background process"
if (sleep 0.1 &) 2>/dev/null; then
    test_pass
else
    test_fail "Background process creation failed"
fi

test_start "Process substitution works"
if current_pid=$$; [ -n "$current_pid" ] && [ "$current_pid" -gt 0 ]; then
    test_pass
else
    test_fail "Cannot get current PID"
fi

test_start "kill command exists"
if test_command_exists kill; then
    test_pass
else
    test_fail "kill command not found"
fi

test_start "sleep command exists"
if test_command_exists sleep; then
    test_pass
else
    test_fail "sleep command not found"
fi

test_start "sleep command works"
if sleep 0.1 2>/dev/null; then
    test_pass
else
    test_fail "sleep execution failed"
fi

test_start "true command returns success"
if true 2>/dev/null; then
    test_pass
else
    test_fail "true command failed"
fi

test_start "false command returns failure"
if ! false 2>/dev/null; then
    test_pass
else
    test_fail "false command succeeded unexpectedly"
fi

test_start "Exit codes are preserved"
if sh -c 'exit 42'; then
    exit_val=$?
    test_fail "Exit code not propagated"
else
    exit_val=$?
    if [ $exit_val -eq 42 ]; then
        test_pass
    else
        test_fail "Exit code incorrect (got $exit_val, expected 42)"
    fi
fi

test_start "Environment variables are accessible"
if [ -n "$PATH" ] && [ -n "$HOME" ]; then
    test_pass
else
    test_fail "Essential environment variables missing"
fi

test_start "Can set and read environment variables"
if TEST_VAR="test_value"; export TEST_VAR; [ "$TEST_VAR" = "test_value" ]; then
    test_pass
else
    test_fail "Environment variable handling failed"
fi

test_start "env command exists"
if test_command_exists env; then
    test_pass
else
    test_fail "env command not found"
fi

test_start "env can display environment"
if env >/dev/null 2>&1; then
    test_pass
else
    test_fail "env execution failed"
fi
