#!/bin/sh
# Test: Memory and Resource Operations
# Validates memory management and resource handling

TEST_DIR="/tmp/penv-memory-test-$$"

setup_test_env() {
    mkdir -p "$TEST_DIR" 2>/dev/null || return 1
    return 0
}

cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

trap cleanup_test_env EXIT INT TERM

test_start "Setup memory test environment"
if setup_test_env; then
    test_pass
else
    test_fail "Cannot create test directory"
fi

test_start "Can allocate small strings"
if small_string="test string" && [ -n "$small_string" ]; then
    test_pass
else
    test_fail "Small string allocation failed"
fi

test_start "Can allocate medium-sized data"
if medium_data=$(awk 'BEGIN{for(i=0;i<100;i++)printf "#"}') && [ ${#medium_data} -eq 100 ]; then
    test_pass
else
    test_fail "Medium data allocation failed"
fi

test_start "Can allocate and free multiple variables"
if var1="data1" && var2="data2" && var3="data3" && unset var1 var2 var3; then
    test_pass
else
    test_fail "Variable allocation/deallocation failed"
fi

test_start "File buffering works correctly"
if echo "buffered write" > "$TEST_DIR/buffer" && sync && [ -f "$TEST_DIR/buffer" ]; then
    test_pass
else
    test_fail "File buffering failed"
fi

test_start "Can create multiple files"
if touch "$TEST_DIR/file1" "$TEST_DIR/file2" "$TEST_DIR/file3" 2>/dev/null; then
    count=$(ls "$TEST_DIR"/file* 2>/dev/null | wc -l)
    if [ "$count" -eq 3 ]; then
        test_pass
    else
        test_fail "Multiple file creation failed"
    fi
else
    test_fail "Cannot create multiple files"
fi

test_start "File descriptor limits are reasonable"
if (exec 3>&1 && exec 4>&1 && exec 5>&1 && exec 3>&- && exec 4>&- && exec 5>&-) 2>/dev/null; then
    test_pass
else
    test_fail "File descriptor operations failed"
fi

test_start "Can read and write repeatedly"
success=true
for i in 1 2 3 4 5; do
    if ! echo "test$i" > "$TEST_DIR/repeat_test" 2>/dev/null; then
        success=false
        break
    fi
done
if $success; then
    test_pass
else
    test_fail "Repeated I/O operations failed"
fi

test_start "Memory operations with loops work"
if counter=0; [ $counter -eq 0 ]; then
    counter=$((counter + 1))
    counter=$((counter + 1))
    counter=$((counter + 1))
    if [ $counter -eq 3 ]; then
        test_pass
    else
        test_fail "Loop counter failed"
    fi
else
    test_fail "Counter initialization failed"
fi

test_start "Temporary file creation works"
if temp_file=$(mktemp "$TEST_DIR/temp.XXXXXX" 2>&1) && [ -f "$temp_file" ]; then
    test_pass
    rm -f "$temp_file"
else
    test_skip "mktemp not available or failed"
fi

test_start "Zero-byte file operations work"
if touch "$TEST_DIR/empty" && [ ! -s "$TEST_DIR/empty" ]; then
    test_pass
else
    test_fail "Empty file handling failed"
fi

test_start "Large(r) file operations work"
if dd if=/dev/zero of="$TEST_DIR/large" bs=1024 count=10 >/dev/null 2>&1; then
    size=$(stat -c %s "$TEST_DIR/large" 2>/dev/null)
    if [ "$size" -eq 10240 ]; then
        test_pass
    else
        test_fail "Large file size incorrect: $size"
    fi
else
    test_skip "dd not available"
fi

test_start "Memory cleanup works (file removal)"
if touch "$TEST_DIR/cleanup_test" && rm "$TEST_DIR/cleanup_test" && [ ! -f "$TEST_DIR/cleanup_test" ]; then
    test_pass
else
    test_fail "Cleanup failed"
fi

test_start "Recursive operations work"
if mkdir -p "$TEST_DIR/a/b/c/d" && [ -d "$TEST_DIR/a/b/c/d" ]; then
    test_pass
else
    test_fail "Recursive directory creation failed"
fi

test_start "Stack operations (via subshells) work"
if result=$(echo $(echo $(echo "nested"))); [ "$result" = "nested" ]; then
    test_pass
else
    test_fail "Nested operations failed"
fi

test_start "Process resource limits are functional"
if ulimit -n >/dev/null 2>&1; then
    test_pass
else
    test_skip "ulimit not available"
fi
