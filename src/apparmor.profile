abi <abi/4.0>,
include <tunables/global>

# AppArmor profile for penv and rootbox
# rootbox creates user/mount/PID namespaces for isolated chroot environments
profile penv-rootbox /{usr/,usr/local/}bin/{penv,rootbox} flags=(complain) {
  include <abstractions/base>
  
  # Allow user namespace creation (required for unshare(CLONE_NEWUSER))
  userns,
  
  # Allow capability operations within the user namespace
  capability,
  
  # Allow reading and executing the binaries
  /{usr/,usr/local/}bin/penv mr,
  /{usr/,usr/local/}bin/rootbox mrix,
  
  # Allow access to system-installed penv environments (not user-writable)
  /opt/penv/envs/** rwlix,
  /var/lib/penv/envs/** rwlix,
  
  # Allow executing shells and binaries within chroot
  /{usr/,}{bin,sbin}/** ix,
  /opt/**/bin/** ix,
  
  # Allow proc/sys access for namespace operations
  @{PROC}/** rw,
  /sys/** r,
  
  # Allow /dev access for terminal operations
  /dev/** rw,
  
  # Allow temporary file operations
  /tmp/** rw,
  /var/tmp/** rw,
  
  # Allow writing uid_map and gid_map for user namespace setup
  @{PROC}/@{pid}/uid_map w,
  @{PROC}/@{pid}/gid_map w,
  @{PROC}/@{pid}/setgroups w,

  # Site-specific additions and overrides
  include if exists <local/penv-rootbox>
}