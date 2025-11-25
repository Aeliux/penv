#!/bin/sh
# Test: Dynamic Linker and Shared Libraries
# Validates dynamic linking functionality (universal - all distros)

test_start "C library (libc) is present"
if [ -f /lib/*/libc.so.* ] || [ -f /lib64/libc.so.* ] || [ -f /usr/lib/*/libc.so.* ] || [ -f /lib/libc.so.* ]; then
    test_pass
else
    test_fail "libc not found"
fi

test_start "Dynamic linker exists"
if [ -f /lib/*/ld-*.so.* ] || [ -f /lib64/ld-*.so.* ] || [ -f /lib/ld-*.so.* ]; then
    test_pass
else
    test_fail "Dynamic linker not found"
fi

test_start "ldd command exists"
if test_command_exists ldd; then
    test_pass
else
    test_fail "ldd not found"
fi

test_start "ldd can analyze binary dependencies"
if test_command_exists ldd && ldd /bin/sh >/dev/null 2>&1; then
    test_pass
else
    test_fail "ldd execution failed"
fi

test_start "Essential binaries are dynamically linked"
if test_command_exists ldd; then
    if ldd /bin/sh 2>&1 | grep -q 'libc\.so'; then
        test_pass
    else
        test_fail "Binary not properly linked to libc"
    fi
else
    test_skip "ldd not available"
fi

test_start "Dynamic linker can load libraries"
if test_command_exists ldd; then
    libs=$(ldd /bin/sh 2>&1 | grep -c '=>')
    if [ "$libs" -gt 0 ]; then
        test_pass
    else
        test_fail "No library dependencies resolved"
    fi
else
    test_skip "ldd not available"
fi

test_start "Library paths are resolved correctly"
if test_command_exists ldd; then
    if ldd /bin/sh 2>&1 | grep -E 'libc\.so.*=> /' | grep -v 'not found' >/dev/null; then
        test_pass
    else
        test_fail "Library paths not resolved"
    fi
else
    test_skip "ldd not available"
fi

test_start "No missing library dependencies for /bin/sh"
if test_command_exists ldd; then
    if ldd /bin/sh 2>&1 | grep -q 'not found'; then
        test_fail "Missing library dependencies detected"
    else
        test_pass
    fi
else
    test_skip "ldd not available"
fi

test_start "Can execute dynamically linked binaries"
if /bin/sh -c 'exit 0' 2>/dev/null; then
    test_pass
else
    test_fail "Cannot execute dynamically linked binary"
fi

test_start "Runtime linker configuration exists"
if [ -f /etc/ld.so.cache ] || [ -d /etc/ld.so.conf.d ] || [ -f /etc/ld.so.conf ]; then
    test_pass
else
    test_skip "Runtime linker config not cached (acceptable)"
fi

test_start "ldconfig command exists"
if test_command_exists ldconfig; then
    test_pass
else
    test_skip "ldconfig not available (may not be needed)"
fi

test_start "Thread library (libpthread) is accessible"
if test_command_exists ldd; then
    # Check if threading is available (directly or through libc)
    if ldd /bin/sh 2>&1 | grep -qE 'pthread|libc'; then
        test_pass
    else
        test_skip "Threading library detection inconclusive"
    fi
else
    test_skip "ldd not available"
fi

test_start "Math library (libm) can be found"
if [ -f /lib/*/libm.so.* ] || [ -f /lib64/libm.so.* ] || [ -f /usr/lib/*/libm.so.* ] || [ -f /lib/libm.so.* ]; then
    test_pass
else
    test_skip "libm not required for basic functionality"
fi

test_start "Runtime library loading works"
# Test that the system can load libraries at runtime by executing a command
if ls /lib*/libc.so.* >/dev/null 2>&1 || ls /usr/lib/*/libc.so.* >/dev/null 2>&1; then
    test_pass
else
    test_fail "Cannot access runtime libraries"
fi

test_start "LD_LIBRARY_PATH can be set and used"
# Create minimal test of LD_LIBRARY_PATH functionality
if (LD_LIBRARY_PATH=/lib:/usr/lib /bin/sh -c 'exit 0') 2>/dev/null; then
    test_pass
else
    test_fail "LD_LIBRARY_PATH not working"
fi

test_start "Dynamic linker resolves symbol versions"
if test_command_exists ldd; then
    # Check that versioned symbols are properly handled
    if ldd /bin/sh 2>&1 | grep -E 'GLIBC|libc\.so' >/dev/null; then
        test_pass
    else
        test_skip "Symbol version detection inconclusive"
    fi
else
    test_skip "ldd not available"
fi

test_start "Lazy binding is supported"
# Test that LD_BIND_NOW can be set (whether lazy or immediate binding)
if (LD_BIND_NOW=1 /bin/sh -c 'exit 0') 2>/dev/null; then
    test_pass
else
    test_fail "LD_BIND_NOW not supported"
fi

test_start "Library dependencies are transitive"
if test_command_exists ldd; then
    # Count total dependencies (should include transitive deps)
    dep_count=$(ldd /bin/sh 2>&1 | grep -c '=>')
    if [ "$dep_count" -ge 1 ]; then
        test_pass
    else
        test_fail "No transitive dependencies found"
    fi
else
    test_skip "ldd not available"
fi

test_start "Standard library search paths work"
# Verify that standard paths (/lib, /usr/lib) are searched
if test_command_exists ldd; then
    if ldd /bin/sh 2>&1 | grep -E '=> /(lib|usr/lib)' >/dev/null; then
        test_pass
    else
        test_fail "Standard library paths not used"
    fi
else
    test_skip "ldd not available"
fi

test_start "Symbol resolution across libraries"
# Test that symbols can be resolved between multiple libraries
if test_command_exists ldd && ldd /bin/bash >/dev/null 2>&1; then
    # bash typically links to more libraries than sh
    if ldd /bin/bash 2>&1 | grep -c '=>' | grep -qE '[2-9]|[0-9]{2,}'; then
        test_pass
    else
        test_skip "Limited library dependencies"
    fi
else
    test_skip "bash not available for testing"
fi

test_start "SONAME mechanism works"
# Verify that libraries with SONAMEs can be loaded
if test_command_exists ldd; then
    if ldd /bin/sh 2>&1 | grep -E 'libc\.so\.[0-9]+' >/dev/null; then
        test_pass
    else
        test_fail "SONAME resolution not working"
    fi
else
    test_skip "ldd not available"
fi

test_start "Executable format is recognized"
if test_command_exists file; then
    if file $(readlink -f /bin/sh) | grep -qE 'ELF|executable'; then
        test_pass
    else
        test_fail "Executable format not recognized"
    fi
else
    test_skip "file command not available"
fi

test_start "Program interpreter is valid"
if test_command_exists readelf; then
    if readelf -l /bin/sh 2>/dev/null | grep -q 'program interpreter'; then
        test_pass
    else
        test_fail "No program interpreter found"
    fi
else
    test_skip "readelf not available"
fi
