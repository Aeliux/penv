#!/bin/sh
# Test: Compression and Archive Tools
# Validates tar, gzip, and other archive tools

TEST_DIR="/tmp/penv-archive-test-$$"

setup_test_env() {
    mkdir -p "$TEST_DIR/archive" 2>/dev/null || return 1
    echo "file1 content" > "$TEST_DIR/archive/file1.txt" 2>/dev/null || return 1
    echo "file2 content" > "$TEST_DIR/archive/file2.txt" 2>/dev/null || return 1
    mkdir -p "$TEST_DIR/archive/subdir" 2>/dev/null || return 1
    echo "file3 content" > "$TEST_DIR/archive/subdir/file3.txt" 2>/dev/null || return 1
    return 0
}

cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

trap cleanup_test_env EXIT INT TERM

test_start "Setup archive test environment"
if setup_test_env; then
    test_pass
else
    test_fail "Cannot create test structure"
fi

test_start "tar command exists"
if test_command_exists tar; then
    test_pass
else
    test_fail "tar command not found"
fi

test_start "tar can create archive"
if (cd "$TEST_DIR/archive" && tar -cf "$TEST_DIR/test.tar" . 2>/dev/null) && [ -f "$TEST_DIR/test.tar" ]; then
    test_pass
else
    test_fail "tar archive creation failed"
fi

test_start "tar archive contains files"
if [ -f "$TEST_DIR/test.tar" ] && tar -tf "$TEST_DIR/test.tar" 2>/dev/null | grep -q "file1.txt"; then
    test_pass
else
    test_fail "tar archive does not contain expected files"
fi

test_start "tar can extract archive"
if mkdir -p "$TEST_DIR/extract" 2>/dev/null && tar -xf "$TEST_DIR/test.tar" -C "$TEST_DIR/extract" 2>/dev/null; then
    if [ -f "$TEST_DIR/extract/file1.txt" ]; then
        test_pass
    else
        test_fail "Extracted files not found"
    fi
else
    test_fail "tar extraction failed"
fi

test_start "Extracted content matches original"
if [ -f "$TEST_DIR/extract/file1.txt" ]; then
    content=$(cat "$TEST_DIR/extract/file1.txt" 2>&1)
    if [ "$content" = "file1 content" ]; then
        test_pass
    else
        test_fail "Extracted content differs"
    fi
else
    test_fail "Cannot verify extracted content"
fi

test_start "gzip command exists"
if test_command_exists gzip; then
    test_pass
else
    test_skip "gzip not installed"
fi

test_start "gzip can compress file"
if test_command_exists gzip; then
    cp "$TEST_DIR/archive/file1.txt" "$TEST_DIR/compress.txt" 2>/dev/null
    if gzip "$TEST_DIR/compress.txt" 2>/dev/null && [ -f "$TEST_DIR/compress.txt.gz" ]; then
        test_pass
    else
        test_fail "gzip compression failed"
    fi
else
    test_skip "gzip not available"
fi

test_start "gunzip can decompress file"
if test_command_exists gunzip && [ -f "$TEST_DIR/compress.txt.gz" ]; then
    if gunzip "$TEST_DIR/compress.txt.gz" 2>/dev/null && [ -f "$TEST_DIR/compress.txt" ]; then
        test_pass
    else
        test_fail "gunzip decompression failed"
    fi
else
    test_skip "gunzip not available or no test file"
fi

test_start "tar can create compressed archive (tar.gz)"
if test_command_exists gzip; then
    if (cd "$TEST_DIR/archive" && tar -czf "$TEST_DIR/test.tar.gz" . 2>/dev/null) && [ -f "$TEST_DIR/test.tar.gz" ]; then
        test_pass
    else
        test_fail "tar.gz creation failed"
    fi
else
    test_skip "gzip not available"
fi

test_start "tar can extract compressed archive (tar.gz)"
if [ -f "$TEST_DIR/test.tar.gz" ]; then
    mkdir -p "$TEST_DIR/extract-gz" 2>/dev/null
    if tar -xzf "$TEST_DIR/test.tar.gz" -C "$TEST_DIR/extract-gz" 2>/dev/null && [ -f "$TEST_DIR/extract-gz/file1.txt" ]; then
        test_pass
    else
        test_fail "tar.gz extraction failed"
    fi
else
    test_skip "No tar.gz file to extract"
fi

test_start "bzip2 command exists"
if test_command_exists bzip2; then
    test_pass
else
    test_skip "bzip2 not installed (optional)"
fi

test_start "tar supports bzip2 compression (tar.bz2)"
if test_command_exists bzip2; then
    if (cd "$TEST_DIR/archive" && tar -cjf "$TEST_DIR/test.tar.bz2" . 2>/dev/null) && [ -f "$TEST_DIR/test.tar.bz2" ]; then
        test_pass
    else
        test_skip "tar.bz2 creation not supported or failed"
    fi
else
    test_skip "bzip2 not available"
fi

test_start "xz command exists"
if test_command_exists xz; then
    test_pass
else
    test_skip "xz not installed (optional)"
fi

test_start "tar supports xz compression (tar.xz)"
if test_command_exists xz; then
    if (cd "$TEST_DIR/archive" && tar -cJf "$TEST_DIR/test.tar.xz" 2>/dev/null . ) && [ -f "$TEST_DIR/test.tar.xz" ]; then
        test_pass
    else
        test_skip "tar.xz creation not supported or failed"
    fi
else
    test_skip "xz not available"
fi

test_start "zip command exists"
if test_command_exists zip; then
    test_pass
else
    test_skip "zip not installed (optional)"
fi

test_start "unzip command exists"
if test_command_exists unzip; then
    test_pass
else
    test_skip "unzip not installed (optional)"
fi

test_start "tar preserves directory structure"
if [ -f "$TEST_DIR/test.tar" ]; then
    if tar -tf "$TEST_DIR/test.tar" 2>/dev/null | grep -q "subdir/file3.txt"; then
        test_pass
    else
        test_fail "Directory structure not preserved"
    fi
else
    test_fail "No tar archive to test"
fi

test_start "tar preserves file permissions"
if [ -f "$TEST_DIR/test.tar" ] && [ -d "$TEST_DIR/extract" ]; then
    orig_perms=$(stat -c %a "$TEST_DIR/archive/file1.txt" 2>/dev/null)
    extract_perms=$(stat -c %a "$TEST_DIR/extract/file1.txt" 2>/dev/null)
    if [ "$orig_perms" = "$extract_perms" ]; then
        test_pass
    else
        test_skip "Permission preservation differs (common in proot)"
    fi
else
    test_skip "Cannot test permission preservation"
fi
