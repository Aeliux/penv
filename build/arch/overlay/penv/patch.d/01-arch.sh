#!/bin/sh

set -e

install -d /etc/pacman.d/hooks
cat > /etc/pacman.d/hooks/99-clean-paccache.hook <<'EOF'
[Trigger]
Operation = Install
Operation = Upgrade
Operation = Remove
Type = Package
Target = *

[Action]
Description = Remove pacman package cache
When = PostTransaction
Exec = /bin/bash -c 'rm -rf /var/cache/pacman/pkg/*'
EOF

# Update package database and upgrade base packages
pacman -Syu --noconfirm --noprogressbar 

# Link ping to ping6 for compatibility
ln -sf /usr/bin/ping /usr/bin/ping6
