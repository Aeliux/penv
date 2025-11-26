#!/bin/sh
# Test: Debian Service Management
# Validates init system and service configuration

test_start "systemd is present or alternatives available"
if test_command_exists systemctl || test_dir_exists /etc/init.d; then
    test_pass
else
    test_skip "No init system detected (container environment)"
fi

test_start "/etc/init.d directory exists"
if test_dir_exists /etc/init.d; then
    test_pass
else
    test_skip "/etc/init.d not present (systemd-only)"
fi

test_start "service command exists"
if test_command_exists service; then
    test_pass
else
    test_skip "service command not available"
fi

test_start "/etc/systemd directory exists (if systemd)"
if test_command_exists systemctl; then
    if test_dir_exists /etc/systemd; then
        test_pass
    else
        test_fail "/etc/systemd missing"
    fi
else
    test_skip "Not a systemd system"
fi

test_start "SYSTEMD_OFFLINE environment variable set"
if [ "$SYSTEMD_OFFLINE" = "1" ]; then
    test_pass
else
    test_skip "SYSTEMD_OFFLINE not set (may not be needed)"
fi

test_start "/run directory exists for runtime data"
if test_dir_exists /run; then
    test_pass
else
    test_skip "/run not present (older systems)"
fi

test_start "update-rc.d command exists"
if test_command_exists update-rc.d; then
    test_pass
else
    test_skip "update-rc.d not available (systemd-only system)"
fi

test_start "invoke-rc.d command exists"
if test_command_exists invoke-rc.d; then
    test_pass
else
    test_skip "invoke-rc.d not available"
fi

test_start "System logging directory exists"
if test_dir_exists /var/log; then
    test_pass
else
    test_fail "/var/log missing"
fi

test_start "dbus directory exists (if dbus available)"
if test_dir_exists /var/lib/dbus || test_dir_exists /etc/dbus-1; then
    test_pass
else
    test_skip "D-Bus not configured (optional)"
fi
