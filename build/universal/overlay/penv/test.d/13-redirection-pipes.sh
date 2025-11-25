#!/bin/sh
# Test: I/O Redirection and Pipes
# Validates shell redirection and piping work correctly

TEST_DIR="/tmp/penv-io-test-$$"

setup_test_env() {
    mkdir -p "$TEST_DIR" 2>/dev/null || return 1
    return 0
}

cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

trap cleanup_test_env EXIT INT TERM

test_start "Setup I/O test environment"
if setup_test_env; then
    test_pass
else
    test_fail "Cannot create test directory"
fi

test_start "Output redirection (>) works"
if echo "test" > "$TEST_DIR/output.txt" 2>/dev/null && [ -f "$TEST_DIR/output.txt" ]; then
    test_pass
else
    test_fail "Output redirection failed"
fi

test_start "Redirected content is correct"
if echo "test content" > "$TEST_DIR/redirect.txt" 2>/dev/null; then
    content=$(cat "$TEST_DIR/redirect.txt" 2>&1)
    if [ "$content" = "test content" ]; then
        test_pass
    else
        test_fail "Redirected content incorrect"
    fi
else
    test_fail "Cannot write redirected content"
fi

test_start "Output append (>>) works"
if echo "line1" > "$TEST_DIR/append.txt" 2>/dev/null && echo "line2" >> "$TEST_DIR/append.txt" 2>/dev/null; then
    lines=$(wc -l < "$TEST_DIR/append.txt" 2>&1)
    if [ "$lines" -eq 2 ]; then
        test_pass
    else
        test_fail "Append redirection failed (got $lines lines)"
    fi
else
    test_fail "Cannot append to file"
fi

test_start "Input redirection (<) works"
if echo "input test" > "$TEST_DIR/input.txt" 2>/dev/null; then
    result=$(cat < "$TEST_DIR/input.txt" 2>&1)
    if [ "$result" = "input test" ]; then
        test_pass
    else
        test_fail "Input redirection failed"
    fi
else
    test_fail "Cannot setup input redirection test"
fi

test_start "Error redirection (2>) works"
if sh -c 'echo error >&2' 2> "$TEST_DIR/error.txt" && [ -s "$TEST_DIR/error.txt" ]; then
    test_pass
else
    test_fail "Error redirection failed"
fi

test_start "Combined stdout and stderr (2>&1) works"
if (echo "stdout"; echo "stderr" >&2) > "$TEST_DIR/combined.txt" 2>&1; then
    lines=$(wc -l < "$TEST_DIR/combined.txt" 2>&1)
    if [ "$lines" -eq 2 ]; then
        test_pass
    else
        test_fail "Combined redirection failed"
    fi
else
    test_fail "Cannot combine output streams"
fi

test_start "Simple pipe (|) works"
if result=$(echo "test" | cat 2>&1) && [ "$result" = "test" ]; then
    test_pass
else
    test_fail "Simple pipe failed"
fi

test_start "Multiple pipes work"
if result=$(echo "hello world" | sed 's/world/universe/' | sed 's/hello/goodbye/' 2>&1) && [ "$result" = "goodbye universe" ]; then
    test_pass
else
    test_fail "Multiple pipes failed"
fi

test_start "Pipe with grep filtering"
if result=$(printf "line1\nline2\nline3" | grep "line2" 2>&1) && [ "$result" = "line2" ]; then
    test_pass
else
    test_fail "Pipe with grep failed"
fi

test_start "Pipe preserves line count"
if lines=$(printf "1\n2\n3\n4\n5\n" | cat | wc -l 2>&1 | tr -d ' ') && [ "$lines" -eq 5 ]; then
    test_pass
else
    test_fail "Pipe line count incorrect"
fi

test_start "/dev/null is writable"
if echo "discard" > /dev/null 2>&1; then
    test_pass
else
    test_fail "/dev/null not writable"
fi

test_start "/dev/null discards output"
if echo "test" > /dev/null 2>&1 && [ ! -s /dev/null ]; then
    test_pass
else
    test_fail "/dev/null not functioning correctly"
fi

test_start "/dev/zero is readable"
if dd if=/dev/zero of="$TEST_DIR/zeros" bs=1 count=10 >/dev/null 2>&1 && [ -s "$TEST_DIR/zeros" ]; then
    test_pass
else
    test_skip "/dev/zero not available or dd failed"
fi

test_start "Here document (<<) works"
if cat > "$TEST_DIR/heredoc.txt" << 'EOF' 2>/dev/null
line 1
line 2
EOF
    [ -f "$TEST_DIR/heredoc.txt" ] && [ "$(wc -l < "$TEST_DIR/heredoc.txt")" -eq 2 ]; then
    test_pass
else
    test_fail "Here document failed"
fi

test_start "Here string (<<<) works"
# Use bash explicitly since here-string is a bashism
if result=$(bash -c 'cat <<< "here string"' 2>&1) && [ "$result" = "here string" ]; then
    test_pass
else
    test_fail "Here string failed (bash required)"
fi

test_start "Command substitution with pipes"
if result=$(echo "TEST" | tr 'A-Z' 'a-z') && [ "$result" = "test" ]; then
    test_pass
else
    test_fail "Command substitution with pipe failed"
fi

test_start "Nested command substitution works"
if result=$(echo $(echo "nested")) && [ "$result" = "nested" ]; then
    test_pass
else
    test_fail "Nested command substitution failed"
fi

test_start "tee command duplicates output"
if test_command_exists tee; then
    result=$(echo "test" | tee "$TEST_DIR/tee.txt" 2>&1)
    if [ "$result" = "test" ] && [ -f "$TEST_DIR/tee.txt" ] && [ "$(cat "$TEST_DIR/tee.txt")" = "test" ]; then
        test_pass
    else
        test_fail "tee command failed"
    fi
else
    test_skip "tee command not available"
fi

test_start "xargs command processes input"
if test_command_exists xargs; then
    result=$(echo "arg1 arg2 arg3" | xargs echo 2>&1)
    if [ "$result" = "arg1 arg2 arg3" ]; then
        test_pass
    else
        test_fail "xargs failed"
    fi
else
    test_skip "xargs not available"
fi
