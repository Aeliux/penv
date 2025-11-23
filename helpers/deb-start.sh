#!/bin/sh

# Debian-specific runtime environment setup
# Source this before launching the shell in Debian-based environments

# Configure dpkg to work in proot
export DPKG_ADMINDIR=/var/lib/dpkg

# Disable apt sandboxing for proot compatibility
export APT_CONFIG=/etc/apt/apt.conf.d/99proot

# Fix for some apt operations in proot
export DEBIAN_FRONTEND=noninteractive
export DEBCONF_NONINTERACTIVE_SEEN=true
