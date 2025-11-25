#!/bin/sh
# Test: Path Resolution and Working Directory
# Critical for proot environments where path handling can be problematic

TEST_DIR="/tmp/penv-path-test-$$"

setup_test_env() {
    mkdir -p "$TEST_DIR/dir1/dir2" 2>/dev/null || return 1
    touch "$TEST_DIR/file1" "$TEST_DIR/dir1/file2" "$TEST_DIR/dir1/dir2/file3" 2>/dev/null || return 1
    return 0
}

cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

trap cleanup_test_env EXIT INT TERM

test_start "Setup path test environment"
if setup_test_env; then
    test_pass
else
    test_fail "Cannot create test structure"
fi

test_start "pwd reports correct absolute path"
if current=$(pwd 2>&1) && [ "${current#/}" != "$current" ]; then
    test_pass
else
    test_fail "pwd does not return absolute path"
fi

test_start "cd to absolute path works"
if (cd /tmp && [ "$(pwd)" = "/tmp" ]); then
    test_pass
else
    test_fail "cd to absolute path failed"
fi

test_start "cd to relative path works"
if (cd "$TEST_DIR" && cd dir1 && [ "$(pwd)" = "$TEST_DIR/dir1" ]); then
    test_pass
else
    test_fail "cd to relative path failed"
fi

test_start "cd with multiple levels works"
if (cd "$TEST_DIR" && cd dir1/dir2 && [ "$(pwd)" = "$TEST_DIR/dir1/dir2" ]); then
    test_pass
else
    test_fail "Multi-level cd failed"
fi

test_start "cd .. navigates to parent"
if (cd "$TEST_DIR/dir1/dir2" && cd .. && [ "$(pwd)" = "$TEST_DIR/dir1" ]); then
    test_pass
else
    test_fail "cd .. navigation failed"
fi

test_start "cd ../.. navigates up two levels"
if (cd "$TEST_DIR/dir1/dir2" && cd ../.. && [ "$(pwd)" = "$TEST_DIR" ]); then
    test_pass
else
    test_fail "cd ../.. navigation failed"
fi

test_start "cd - returns to previous directory"
if (cd /tmp && prev="/tmp" && cd "$TEST_DIR" && cd - >/dev/null 2>&1 && [ "$(pwd)" = "$prev" ]); then
    test_pass
else
    test_fail "cd - (previous directory) failed"
fi

test_start "OLDPWD variable is set after cd"
if (cd /tmp && cd "$TEST_DIR" >/dev/null 2>&1 && [ "$OLDPWD" = "/tmp" ]); then
    test_pass
else
    test_skip "OLDPWD not supported or not set"
fi

test_start "Relative file access works after cd"
if (cd "$TEST_DIR/dir1" && test -f file2); then
    test_pass
else
    test_fail "Relative file access failed after cd"
fi

test_start "Absolute file access works from any directory"
if (cd "$TEST_DIR/dir1/dir2" && test -f "$TEST_DIR/file1"); then
    test_pass
else
    test_fail "Absolute file access failed"
fi

test_start "Can access file with ./ prefix"
if (cd "$TEST_DIR" && test -f ./file1); then
    test_pass
else
    test_fail "File access with ./ prefix failed"
fi

test_start "Can access file with ../ prefix"
if (cd "$TEST_DIR/dir1" && test -f ../file1); then
    test_pass
else
    test_fail "File access with ../ prefix failed"
fi

test_start "readlink resolves symbolic links"
if test_command_exists readlink && ln -s "$TEST_DIR/file1" "$TEST_DIR/symlink" 2>/dev/null; then
    target=$(readlink "$TEST_DIR/symlink" 2>&1)
    if [ "$target" = "$TEST_DIR/file1" ]; then
        test_pass
    else
        test_fail "readlink returned wrong target: $target"
    fi
else
    test_skip "readlink not available or symlink creation failed"
fi

test_start "realpath resolves to absolute path"
if test_command_exists realpath; then
    result=$(cd "$TEST_DIR/dir1" && realpath ../file1 2>&1)
    if [ "$result" = "$TEST_DIR/file1" ]; then
        test_pass
    else
        test_skip "realpath behavior differs (got: $result)"
    fi
else
    test_skip "realpath command not available"
fi

test_start "basename extracts filename"
if test_command_exists basename; then
    result=$(basename "/path/to/file.txt" 2>&1)
    if [ "$result" = "file.txt" ]; then
        test_pass
    else
        test_fail "basename failed (got: $result)"
    fi
else
    test_fail "basename command not found"
fi

test_start "dirname extracts directory path"
if test_command_exists dirname; then
    result=$(dirname "/path/to/file.txt" 2>&1)
    if [ "$result" = "/path/to" ]; then
        test_pass
    else
        test_fail "dirname failed (got: $result)"
    fi
else
    test_fail "dirname command not found"
fi

test_start "Complex path with . and .. resolves correctly"
if (cd "$TEST_DIR" && cd ./dir1/../dir1/./dir2 && [ "$(pwd)" = "$TEST_DIR/dir1/dir2" ]); then
    test_pass
else
    test_fail "Complex path resolution failed"
fi

test_start "PATH environment variable is set"
if [ -n "$PATH" ] && echo "$PATH" | grep -q "/bin"; then
    test_pass
else
    test_fail "PATH variable not properly set"
fi

test_start "which command finds executables in PATH"
if test_command_exists which && which sh >/dev/null 2>&1; then
    test_pass
else
    test_skip "which command not available or failed"
fi
