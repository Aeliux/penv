#!/bin/sh
# Test: File Operations
# Validates ability to create, modify, and delete files

TEST_DIR="/tmp/penv-test-$$"
TEST_FILE="$TEST_DIR/testfile"

# Setup test directory
setup_test_env() {
    mkdir -p "$TEST_DIR" 2>/dev/null || return 1
    return 0
}

# Cleanup test directory
cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

# Ensure cleanup on script exit
trap cleanup_test_env EXIT INT TERM

test_start "Can create test directory"
if setup_test_env; then
    test_pass
else
    test_fail "Failed to create test directory"
fi

test_start "Can create empty file"
if touch "$TEST_FILE" 2>/dev/null; then
    test_pass
else
    test_fail "touch command failed"
fi

test_start "Can write to file"
if echo "test content" > "$TEST_FILE" 2>/dev/null; then
    test_pass
else
    test_fail "File write failed"
fi

test_start "Can read from file"
if content=$(cat "$TEST_FILE" 2>/dev/null) && [ "$content" = "test content" ]; then
    test_pass
else
    test_fail "File read failed"
fi

test_start "Can append to file"
if echo "appended" >> "$TEST_FILE" 2>/dev/null; then
    test_pass
else
    test_fail "File append failed"
fi

test_start "Can copy file"
if cp "$TEST_FILE" "$TEST_FILE.copy" 2>/dev/null; then
    test_pass
else
    test_fail "File copy failed"
fi

test_start "Can move/rename file"
if mv "$TEST_FILE.copy" "$TEST_FILE.moved" 2>/dev/null; then
    test_pass
else
    test_fail "File move failed"
fi

test_start "Can delete file"
if rm "$TEST_FILE.moved" 2>/dev/null; then
    test_pass
else
    test_fail "File deletion failed"
fi

test_start "Can create subdirectory"
if mkdir "$TEST_DIR/subdir" 2>/dev/null; then
    test_pass
else
    test_fail "Subdirectory creation failed"
fi

test_start "Can remove empty directory"
if rmdir "$TEST_DIR/subdir" 2>/dev/null; then
    test_pass
else
    test_fail "Directory removal failed"
fi

test_start "Can check file existence with test command"
if [ -f "$TEST_FILE" ]; then
    test_pass
else
    test_fail "File existence test failed"
fi

test_start "Can check file permissions"
if [ -r "$TEST_FILE" ] && [ -w "$TEST_FILE" ]; then
    test_pass
else
    test_fail "Permission check failed"
fi

test_start "Can modify file permissions"
if chmod 644 "$TEST_FILE" 2>/dev/null && [ "$(stat -c %a "$TEST_FILE" 2>/dev/null)" = "644" ]; then
    test_pass
else
    test_fail "chmod failed"
fi

test_start "File size is reported correctly"
if [ -s "$TEST_FILE" ]; then
    test_pass
else
    test_fail "File size check failed"
fi

# Cleanup happens automatically via trap
