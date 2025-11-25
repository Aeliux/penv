#!/bin/sh
# Test: PENV Integration
# Validates penv-specific functionality and metadata

test_start "PENV metadata file exists"
if test_file_exists /penv/metadata.sh; then
    test_pass
else
    test_fail "/penv/metadata.sh not found"
fi

test_start "PENV version is set"
if [ -n "$PENV_VERSION" ]; then
    test_pass
else
    test_fail "PENV_VERSION not set"
fi

test_start "PENV distro is set"
if [ -n "$PENV_METADATA_DISTRO" ]; then
    test_pass
else
    test_fail "PENV_METADATA_DISTRO not set"
fi

test_start "PENV family is set"
if [ -n "$PENV_METADATA_FAMILY" ]; then
    test_pass
else
    test_fail "PENV_METADATA_FAMILY not set"
fi

test_start "PENV timestamp is set"
if [ -n "$PENV_METADATA_TIMESTAMP" ]; then
    test_pass
else
    test_fail "PENV_METADATA_TIMESTAMP not set"
fi

test_start "PENV startup script exists"
if test_file_exists /penv/startup.sh; then
    test_pass
else
    test_fail "/penv/startup.sh not found"
fi

test_start "PENV startup script is executable"
if test_executable /penv/startup.sh; then
    test_pass
else
    test_fail "/penv/startup.sh not executable"
fi

test_start "PENV startup.d directory exists"
if test_dir_exists /penv/startup.d; then
    test_pass
else
    test_fail "/penv/startup.d directory missing"
fi

test_start "PENV cleanup.d directory exists"
if test_dir_exists /penv/cleanup.d; then
    test_pass
else
    test_fail "/penv/cleanup.d directory missing"
fi

test_start "PENV patch.d directory exists"
if test_dir_exists /penv/patch.d; then
    test_pass
else
    test_fail "/penv/patch.d directory missing"
fi

test_start "PENV signal directory is set"
if [ -n "$PENV_SIGNAL" ]; then
    test_pass
else
    test_fail "PENV_SIGNAL not set"
fi

test_start "PENV environment variables are exported"
if env | grep -q '^PENV_' 2>/dev/null; then
    test_pass
else
    test_fail "No PENV environment variables found"
fi

test_start "penv command exists in PATH"
if test_command_exists penv; then
    test_pass
else
    test_skip "penv command not in PATH (host-side tool)"
fi

test_start "Profile configuration includes penv"
if test_file_exists /etc/profile.d/99-penv.sh; then
    test_pass
else
    test_skip "PENV profile script not found (optional)"
fi
