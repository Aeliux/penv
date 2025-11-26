#!/bin/sh
# Test: PENV Integration
# Validates penv-specific functionality and metadata

test_start "penv metadata file exists"
if test_file_exists /penv/metadata.sh; then
    test_pass
else
    test_fail "/penv/metadata.sh not found"
fi

test_start "penv version is set"
if [ -n "$PENV_VERSION" ]; then
    test_pass
else
    test_fail "PENV_VERSION not set"
fi

test_start "penv distro is set"
if [ -n "$PENV_METADATA_DISTRO" ]; then
    test_pass
else
    test_fail "PENV_METADATA_DISTRO not set"
fi

test_start "penv family is set"
if [ -n "$PENV_METADATA_FAMILY" ]; then
    test_pass
else
    test_fail "PENV_METADATA_FAMILY not set"
fi

test_start "penv timestamp is set"
if [ -n "$PENV_METADATA_TIMESTAMP" ]; then
    test_pass
else
    test_fail "PENV_METADATA_TIMESTAMP not set"
fi

test_start "penv startup script exists"
if test_file_exists /penv/startup.sh; then
    test_pass
else
    test_fail "/penv/startup.sh not found"
fi

test_start "penv startup script is executable"
if test_executable /penv/startup.sh; then
    test_pass
else
    test_fail "/penv/startup.sh not executable"
fi

test_start "Cleanup patches"
if ! test_dir_exists /penv/patch.d; then
    test_pass
else
    test_fail "/penv/patch.d directory exists"
fi

test_start "penv signal directory is set"
if [ -n "$PENV_SIGNAL" ]; then
    test_pass
else
    test_fail "PENV_SIGNAL not set"
fi

test_start "penv environment variables are exported"
if env | grep -q '^PENV_ENV_' 2>/dev/null; then
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
