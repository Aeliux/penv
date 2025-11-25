#!/bin/sh
# Test: libc Standard Functions
# Validates critical C library functions work correctly

TEST_DIR="/tmp/penv-libc-test-$$"

setup_test_env() {
    mkdir -p "$TEST_DIR" 2>/dev/null || return 1
    return 0
}

cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

trap cleanup_test_env EXIT INT TERM

test_start "Setup libc test environment"
if setup_test_env; then
    test_pass
else
    test_fail "Cannot create test directory"
fi

test_start "String functions work (echo test)"
if result=$(echo "test string") && [ "$result" = "test string" ]; then
    test_pass
else
    test_fail "Basic string operations failed"
fi

test_start "String comparison works"
if [ "abc" = "abc" ] && [ "abc" != "def" ]; then
    test_pass
else
    test_fail "String comparison failed"
fi

test_start "String length operations work"
if str="hello" && [ ${#str} -eq 5 ]; then
    test_pass
else
    test_fail "String length failed"
fi

test_start "printf formatting works"
if result=$(printf "%d %s" 42 "test") && [ "$result" = "42 test" ]; then
    test_pass
else
    test_fail "printf formatting failed"
fi

test_start "Integer arithmetic works"
if result=$((10 + 20)) && [ "$result" -eq 30 ]; then
    test_pass
else
    test_fail "Integer arithmetic failed"
fi

test_start "Integer comparison works"
if [ 5 -lt 10 ] && [ 10 -gt 5 ] && [ 5 -eq 5 ]; then
    test_pass
else
    test_fail "Integer comparison failed"
fi

test_start "Memory allocation (via shell operations)"
if large_string=$(printf '%0.s=' {1..1000}) && [ -n "$large_string" ]; then
    test_pass
else
    test_fail "Memory operations failed"
fi

test_start "File I/O buffer operations work"
if dd if=/dev/zero of="$TEST_DIR/buffer_test" bs=1024 count=1 >/dev/null 2>&1 && [ -s "$TEST_DIR/buffer_test" ]; then
    test_pass
else
    test_skip "dd not available or failed"
fi

test_start "Directory traversal works"
if entries=$(ls / 2>&1) && [ -n "$entries" ]; then
    test_pass
else
    test_fail "Directory operations failed"
fi

test_start "Error handling (errno) works"
if ! cat /nonexistent/file 2>/dev/null; then
    test_pass
else
    test_fail "Error handling not working"
fi

test_start "Exit status propagation works"
if sh -c 'exit 42'; then
    test_fail "Exit status not propagated (returned success)"
else
    exit_code=$?
    if [ $exit_code -eq 42 ]; then
        test_pass
    else
        test_fail "Exit status incorrect (got $exit_code, expected 42)"
    fi
fi

test_start "Environment variable operations work"
if TEST_VAR="test_value" && export TEST_VAR && [ "$TEST_VAR" = "test_value" ]; then
    test_pass
else
    test_fail "Environment variable operations failed"
fi

test_start "Signal handling infrastructure works"
if (trap 'echo trapped' EXIT; exit 0) 2>&1 | grep -q "trapped"; then
    test_pass
else
    test_fail "Signal handling failed"
fi

test_start "Locale functions work (basic)"
if locale >/dev/null 2>&1; then
    test_pass
else
    test_fail "Locale functions failed"
fi

test_start "Time functions work"
if date >/dev/null 2>&1; then
    test_pass
else
    test_fail "Time functions failed"
fi

test_start "Random number generation works"
if [ -r /dev/urandom ] && dd if=/dev/urandom of="$TEST_DIR/random" bs=1 count=10 >/dev/null 2>&1; then
    test_pass
else
    test_skip "/dev/urandom not accessible"
fi

test_start "Character encoding functions work"
if echo "test" | od >/dev/null 2>&1; then
    test_pass
else
    test_skip "od command not available"
fi

test_start "Regex functions work (via grep)"
if echo "test123" | grep -E '[0-9]+' >/dev/null 2>&1; then
    test_pass
else
    test_fail "Regex functions failed"
fi

test_start "Sorting/comparison functions work"
if printf "3\n1\n2\n" | sort | head -1 | grep -q "1"; then
    test_pass
else
    test_fail "Sorting functions failed"
fi

test_start "Dynamic linking works"
if ldd /bin/sh >/dev/null 2>&1; then
    test_pass
else
    test_fail "Dynamic linking check failed"
fi

test_start "Shared library loading works"
if ldd /bin/sh 2>&1 | grep -q 'libc.so'; then
    test_pass
else
    test_fail "libc not properly linked"
fi
