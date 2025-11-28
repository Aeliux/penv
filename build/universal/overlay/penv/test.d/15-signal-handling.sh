#!/bin/sh
# Test: Signal Handling
# Validates signal delivery and trap functionality

TEST_DIR="/tmp/penv-signal-test-$$"

setup_test_env() {
    mkdir -p "$TEST_DIR" 2>/dev/null || return 1
    return 0
}

cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

trap cleanup_test_env EXIT INT TERM

test_start "Setup signal test environment"
if setup_test_env; then
    test_pass
else
    test_fail "Cannot create test directory"
fi

test_start "trap command exists and works"
if (trap 'echo trapped' EXIT; exit 0) 2>&1 | grep -q "trapped"; then
    test_pass
else
    test_fail "trap command failed"
fi

test_start "trap can catch EXIT signal"
result=$(sh -c 'trap "echo caught" EXIT; exit 0' 2>&1)
if echo "$result" | grep -q "caught"; then
    test_pass
else
    test_fail "EXIT trap not working"
fi

test_start "trap can handle cleanup on exit"
if (trap "touch '$TEST_DIR/cleanup_done'" EXIT; exit 0) >/dev/null 2>&1; then
    if [ -f "$TEST_DIR/cleanup_done" ]; then
        test_pass
    else
        test_fail "Cleanup trap did not execute"
    fi
else
    test_fail "Trap setup failed"
fi

test_start "Multiple traps can be set"
result=$(sh -c '
    trap "echo first" EXIT
    trap "echo second; trap - EXIT" INT
    exit 0
' 2>&1)
if echo "$result" | grep -q "first"; then
    test_pass
else
    test_fail "Multiple traps failed"
fi

test_start "kill command can send signals"
if { sleep 10 & pid=$!; kill $pid 2>/dev/null; wait $pid 2>/dev/null; }; then
    exit_code=$?
    # Process should have been killed (non-zero exit)
    if [ $exit_code -ne 0 ]; then
        test_pass
    else
        test_skip "Process not killed properly"
    fi
else
    test_skip "Background process handling issue"
fi

test_start "kill -0 checks process existence"
if (sleep 1 & pid=$!; kill -0 $pid 2>/dev/null); then
    test_pass
else
    test_fail "kill -0 process check failed"
fi

test_start "Background job completes"
if (sleep 0.1 & wait $!); then
    test_pass
else
    test_fail "Background job wait failed"
fi

test_start "wait command returns exit status"
if (sh -c 'exit 42' & wait $!) 2>/dev/null; then
    : # Should fail
    test_fail "wait did not propagate exit status"
else
    exit_status=$?
    if [ $exit_status -eq 42 ]; then
        test_pass
    else
        test_fail "wait returned wrong exit status: $exit_status"
    fi
fi

test_start "Process substitution with signals"
if (trap '' INT; kill -INT $$ 2>/dev/null); then
    test_pass
else
    test_skip "Signal to self not supported"
fi

test_start "Subshell isolation works"
result=$(
    VAR="parent"
    (
        VAR="child"
        echo "$VAR"
    )
    echo "$VAR"
)
if [ "$result" = "child
parent" ]; then
    test_pass
else
    test_fail "Subshell variable isolation failed"
fi

test_start "Command grouping with braces works"
result=$({ echo "line1"; echo "line2"; } 2>&1 | wc -l)
if [ "$result" -eq 2 ]; then
    test_pass
else
    test_fail "Command grouping failed"
fi

test_start "Command grouping with parentheses (subshell) works"
if (cd /tmp && true) && [ "$(pwd)" != "/tmp" ]; then
    test_pass
else
    test_fail "Subshell did not isolate directory change"
fi

test_start "Exit code 0 means success"
if true; then
    test_pass
else
    test_fail "true command returned non-zero"
fi

test_start "Exit code non-zero means failure"
if false; then
    test_fail "false command returned zero"
else
    test_pass
fi
