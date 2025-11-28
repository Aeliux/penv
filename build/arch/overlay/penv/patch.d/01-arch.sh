#!/bin/sh

set -e

# Update package database and upgrade base packages
pacman -Syu --noconfirm

# Link ping to ping6 for compatibility
ln -sf /usr/bin/ping /usr/bin/ping6
