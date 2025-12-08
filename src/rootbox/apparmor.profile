abi <abi/4.0>,
include <tunables/global>

# AppArmor profile for penv and rootbox
# rootbox creates user/mount/PID namespaces for isolated chroot environments
profile penv-rootbox /{usr/,usr/local/}bin/{penv,rootbox} flags=(unconfined) {
  # Allow user namespace creation (required for unshare(CLONE_NEWUSER))
  userns,
  
  # Site-specific additions and overrides
  include if exists <local/penv-rootbox>
}