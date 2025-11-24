#!/bin/sh

# Run cleanup only when mode is mod
if [ "$PENV_ENV_MODE" != "mod" ]; then
    exit 0
fi

# Basic cleanup tasks for Debian-based environments

echo "Cleaning up Debian-based environment..."

rm -rf /var/cache/apt/archives/*.deb 2>/dev/null || true
rm -rf /var/lib/apt/lists/* 2>/dev/null || true
