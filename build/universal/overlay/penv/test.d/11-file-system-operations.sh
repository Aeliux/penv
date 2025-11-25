#!/bin/sh
# Test: Advanced File System Operations
# Validates complex file operations work reliably in proot/chroot

TEST_DIR="/tmp/penv-fs-test-$$"

setup_test_env() {
    mkdir -p "$TEST_DIR" 2>/dev/null || return 1
    return 0
}

cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

trap cleanup_test_env EXIT INT TERM

test_start "Setup test environment"
if setup_test_env; then
    test_pass
else
    test_fail "Cannot create test directory"
fi

test_start "Can create nested directory structure"
if mkdir -p "$TEST_DIR/a/b/c/d" 2>/dev/null && test_dir_exists "$TEST_DIR/a/b/c/d"; then
    test_pass
else
    test_fail "Nested directory creation failed"
fi

test_start "Can create symbolic link"
if touch "$TEST_DIR/original" 2>/dev/null && ln -s "$TEST_DIR/original" "$TEST_DIR/link" 2>/dev/null && test_symlink "$TEST_DIR/link"; then
    test_pass
else
    test_fail "Symbolic link creation failed"
fi

test_start "Symbolic link points to correct target"
if test_symlink "$TEST_DIR/link" && [ "$(readlink "$TEST_DIR/link")" = "$TEST_DIR/original" ]; then
    test_pass
else
    test_fail "Symbolic link target incorrect"
fi

test_start "Can read through symbolic link"
if echo "content" > "$TEST_DIR/original" 2>/dev/null && content=$(cat "$TEST_DIR/link" 2>&1) && [ "$content" = "content" ]; then
    test_pass
else
    test_fail "Reading through symlink failed"
fi

test_start "Can create hard link"
if touch "$TEST_DIR/hardlink_original" 2>/dev/null && ln "$TEST_DIR/hardlink_original" "$TEST_DIR/hardlink_copy" 2>/dev/null; then
    test_pass
else
    test_fail "Hard link creation failed"
fi

test_start "Hard link shares same inode"
if [ -f "$TEST_DIR/hardlink_original" ] && [ -f "$TEST_DIR/hardlink_copy" ]; then
    inode1=$(stat -c %i "$TEST_DIR/hardlink_original" 2>/dev/null)
    inode2=$(stat -c %i "$TEST_DIR/hardlink_copy" 2>/dev/null)
    if [ "$inode1" = "$inode2" ]; then
        test_pass
    else
        test_fail "Hard links have different inodes"
    fi
else
    test_fail "Hard link files not found"
fi

test_start "Wildcard expansion works"
if touch "$TEST_DIR/test1.txt" "$TEST_DIR/test2.txt" "$TEST_DIR/test3.txt" 2>/dev/null; then
    count=$(ls "$TEST_DIR"/test*.txt 2>/dev/null | wc -l)
    if [ "$count" -eq 3 ]; then
        test_pass
    else
        test_fail "Wildcard expansion incorrect (got $count files)"
    fi
else
    test_fail "Cannot create test files"
fi

test_start "find command searches directories"
if mkdir -p "$TEST_DIR/search/sub" 2>/dev/null && touch "$TEST_DIR/search/file1" "$TEST_DIR/search/sub/file2" 2>/dev/null; then
    count=$(find "$TEST_DIR/search" -type f 2>/dev/null | wc -l)
    if [ "$count" -eq 2 ]; then
        test_pass
    else
        test_fail "find did not locate all files (found $count)"
    fi
else
    test_fail "Cannot setup find test"
fi

test_start "find supports -name filter"
if touch "$TEST_DIR/findme.txt" "$TEST_DIR/other.txt" 2>/dev/null; then
    if find "$TEST_DIR" -name "findme.txt" 2>/dev/null | grep -q "findme.txt"; then
        test_pass
    else
        test_fail "find -name filter failed"
    fi
else
    test_fail "Cannot create test files"
fi

test_start "File globbing with character classes works"
if touch "$TEST_DIR/a1" "$TEST_DIR/a2" "$TEST_DIR/b1" 2>/dev/null; then
    count=$(ls "$TEST_DIR"/a[0-9] 2>/dev/null | wc -l)
    if [ "$count" -eq 2 ]; then
        test_pass
    else
        test_fail "Character class globbing failed"
    fi
else
    test_fail "Cannot create test files"
fi

test_start "Directory traversal with relative paths works"
if mkdir -p "$TEST_DIR/reltest/sub" 2>/dev/null && touch "$TEST_DIR/reltest/sub/file" 2>/dev/null; then
    (cd "$TEST_DIR/reltest" && test -f sub/file && test -f ./sub/file)
    if [ $? -eq 0 ]; then
        test_pass
    else
        test_fail "Relative path traversal failed"
    fi
else
    test_fail "Cannot setup relative path test"
fi

test_start "Parent directory navigation (..) works"
if mkdir -p "$TEST_DIR/parent/child" 2>/dev/null && touch "$TEST_DIR/parent/file" 2>/dev/null; then
    (cd "$TEST_DIR/parent/child" && test -f ../file)
    if [ $? -eq 0 ]; then
        test_pass
    else
        test_fail "Parent directory navigation failed"
    fi
else
    test_fail "Cannot setup parent directory test"
fi

test_start "Current directory (.) reference works"
if touch "$TEST_DIR/dotfile" 2>/dev/null; then
    (cd "$TEST_DIR" && test -f ./dotfile)
    if [ $? -eq 0 ]; then
        test_pass
    else
        test_fail "Current directory reference failed"
    fi
else
    test_fail "Cannot create test file"
fi

test_start "stat command can read file metadata"
if test_command_exists stat && touch "$TEST_DIR/stattest" 2>/dev/null; then
    if stat "$TEST_DIR/stattest" >/dev/null 2>&1; then
        test_pass
    else
        test_fail "stat command failed"
    fi
else
    test_skip "stat command not available or test setup failed"
fi
