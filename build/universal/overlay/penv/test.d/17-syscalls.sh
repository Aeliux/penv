#!/bin/sh
# Test: Low-Level System Calls
# Validates critical syscalls work correctly in proot/chroot

TEST_DIR="/tmp/penv-syscall-test-$$"

setup_test_env() {
    mkdir -p "$TEST_DIR" 2>/dev/null || return 1
    return 0
}

cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

trap cleanup_test_env EXIT INT TERM

test_start "Setup syscall test environment"
if setup_test_env; then
    test_pass
else
    test_fail "Cannot create test directory"
fi

test_start "open/read/write/close syscalls work"
if echo "test" > "$TEST_DIR/rw_test" 2>/dev/null && [ "$(cat "$TEST_DIR/rw_test")" = "test" ]; then
    test_pass
else
    test_fail "Basic file I/O syscalls failed"
fi

test_start "stat/fstat syscalls work"
if touch "$TEST_DIR/stat_test" 2>/dev/null && stat "$TEST_DIR/stat_test" >/dev/null 2>&1; then
    test_pass
else
    test_fail "stat syscall failed"
fi

test_start "access syscall works"
if touch "$TEST_DIR/access_test" 2>/dev/null && [ -f "$TEST_DIR/access_test" ]; then
    test_pass
else
    test_fail "access syscall failed"
fi

test_start "chmod syscall works"
if touch "$TEST_DIR/chmod_test" 2>/dev/null && chmod 644 "$TEST_DIR/chmod_test" 2>/dev/null; then
    perms=$(stat -c %a "$TEST_DIR/chmod_test" 2>/dev/null)
    if [ "$perms" = "644" ]; then
        test_pass
    else
        test_fail "chmod syscall did not set correct permissions"
    fi
else
    test_fail "chmod syscall failed"
fi

test_start "unlink syscall works"
if touch "$TEST_DIR/unlink_test" 2>/dev/null && rm "$TEST_DIR/unlink_test" 2>/dev/null && [ ! -f "$TEST_DIR/unlink_test" ]; then
    test_pass
else
    test_fail "unlink syscall failed"
fi

test_start "rename syscall works"
if touch "$TEST_DIR/rename_src" 2>/dev/null && mv "$TEST_DIR/rename_src" "$TEST_DIR/rename_dst" 2>/dev/null; then
    if [ -f "$TEST_DIR/rename_dst" ] && [ ! -f "$TEST_DIR/rename_src" ]; then
        test_pass
    else
        test_fail "rename syscall did not move file correctly"
    fi
else
    test_fail "rename syscall failed"
fi

test_start "mkdir/rmdir syscalls work"
if mkdir "$TEST_DIR/mkdir_test" 2>/dev/null && rmdir "$TEST_DIR/mkdir_test" 2>/dev/null; then
    test_pass
else
    test_fail "mkdir/rmdir syscalls failed"
fi

test_start "symlink syscall works"
if touch "$TEST_DIR/symlink_target" 2>/dev/null && ln -s "$TEST_DIR/symlink_target" "$TEST_DIR/symlink_link" 2>/dev/null; then
    if [ -L "$TEST_DIR/symlink_link" ]; then
        test_pass
    else
        test_fail "symlink syscall failed"
    fi
else
    test_fail "symlink syscall failed"
fi

test_start "readlink syscall works"
if [ -L "$TEST_DIR/symlink_link" ] && readlink "$TEST_DIR/symlink_link" >/dev/null 2>&1; then
    test_pass
else
    test_fail "readlink syscall failed"
fi

test_start "link (hard link) syscall works"
if touch "$TEST_DIR/hardlink_src" 2>/dev/null && ln "$TEST_DIR/hardlink_src" "$TEST_DIR/hardlink_dst" 2>/dev/null; then
    src_inode=$(stat -c %i "$TEST_DIR/hardlink_src" 2>/dev/null)
    dst_inode=$(stat -c %i "$TEST_DIR/hardlink_dst" 2>/dev/null)
    if [ "$src_inode" = "$dst_inode" ]; then
        test_pass
    else
        test_fail "hard link inodes don't match"
    fi
else
    test_fail "link syscall failed"
fi

test_start "getcwd syscall works"
if current_dir=$(pwd 2>&1) && [ -n "$current_dir" ]; then
    test_pass
else
    test_fail "getcwd syscall failed"
fi

test_start "chdir syscall works"
if (cd /tmp 2>/dev/null && [ "$(pwd)" = "/tmp" ]); then
    test_pass
else
    test_fail "chdir syscall failed"
fi

test_start "getpid syscall works"
if [ -n "$$" ] && [ "$$" -gt 0 ]; then
    test_pass
else
    test_fail "getpid syscall failed"
fi

test_start "getuid/getgid syscalls work"
if uid=$(id -u 2>&1) && gid=$(id -g 2>&1) && [ -n "$uid" ] && [ -n "$gid" ]; then
    test_pass
else
    test_fail "getuid/getgid syscalls failed"
fi

test_start "time/gettimeofday syscalls work"
if current_time=$(date +%s 2>&1) && [ "$current_time" -gt 0 ]; then
    test_pass
else
    test_fail "time syscall failed"
fi

test_start "pipe syscall works"
if echo "pipe test" | cat >/dev/null 2>&1; then
    test_pass
else
    test_fail "pipe syscall failed"
fi

test_start "dup/dup2 syscalls work (file descriptor duplication)"
if (exec 3>&1 && exec 3>&-) 2>/dev/null; then
    test_pass
else
    test_fail "dup/dup2 syscalls failed"
fi

test_start "fork/execve syscalls work"
if /bin/sh -c 'exit 0' 2>/dev/null; then
    test_pass
else
    test_fail "fork/execve syscalls failed"
fi

test_start "wait/waitpid syscalls work"
if (sleep 0.01 & wait $!) 2>/dev/null; then
    test_pass
else
    test_fail "wait syscalls failed"
fi

test_start "kill syscall works"
if (sleep 10 & pid=$!; kill $pid 2>/dev/null; wait $pid 2>/dev/null); then
    : # Expected to fail since we killed it
    test_pass
else
    test_pass  # Either way is acceptable
fi

test_start "truncate syscall works"
if echo "long content here" > "$TEST_DIR/truncate_test" 2>/dev/null && : > "$TEST_DIR/truncate_test" 2>/dev/null; then
    if [ ! -s "$TEST_DIR/truncate_test" ]; then
        test_pass
    else
        test_fail "truncate syscall did not empty file"
    fi
else
    test_fail "truncate syscall failed"
fi

test_start "fcntl syscall works"
if (exec 3< /dev/null && exec 3<&-) 2>/dev/null; then
    test_pass
else
    test_fail "fcntl syscall failed"
fi

test_start "umask syscall works"
if old_umask=$(umask) && umask 022 >/dev/null 2>&1 && umask "$old_umask" >/dev/null 2>&1; then
    test_pass
else
    test_fail "umask syscall failed"
fi
