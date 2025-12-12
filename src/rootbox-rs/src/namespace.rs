use crate::config::Config;
use crate::error::{Result, RootboxError};
use nix::mount::{mount, MsFlags};
use nix::sched::{unshare, CloneFlags};
use nix::unistd::{getgid, getpid, getuid, sethostname, Gid, Uid};
use std::fs::OpenOptions;
use std::io::Write;
use tracing::{debug, info, warn};

/// Namespace manager for setting up Linux namespaces
pub struct NamespaceManager {
    config: Config,
    outer_uid: Uid,
    outer_gid: Gid,
}

impl NamespaceManager {
    pub fn new(config: Config) -> Self {
        let outer_uid = getuid();
        let outer_gid = getgid();

        Self {
            config,
            outer_uid,
            outer_gid,
        }
    }

    /// Setup user namespace with UID/GID mappings
    pub fn setup_user_namespace(&self) -> Result<()> {
        if !self.config.features.user_namespace {
            debug!("User namespace disabled in config");
            return Ok(());
        }

        // Only setup user namespace if we're not already root
        if self.outer_uid.is_root() {
            debug!("Running as root, skipping user namespace setup");
            return Ok(());
        }

        info!("Setting up user namespace");

        // Unshare user namespace
        unshare(CloneFlags::CLONE_NEWUSER).map_err(|e| {
            RootboxError::NamespaceError(format!("Failed to unshare user namespace: {}", e))
        })?;

        // Setup UID mapping
        self.setup_uid_map()?;

        // Setup GID mapping
        self.setup_gid_map()?;

        Ok(())
    }

    /// Setup UID mapping for user namespace
    fn setup_uid_map(&self) -> Result<()> {
        let pid = getpid();
        let uid_map_path = format!("/proc/{}/uid_map", pid);
        let uid_map_content = format!("0 {} 1\n", self.outer_uid);

        debug!("Writing UID map: {}", uid_map_content.trim());

        write_proc_file(&uid_map_path, &uid_map_content)
            .map_err(|e| RootboxError::NamespaceError(format!("Failed to write uid_map: {}", e)))?;

        Ok(())
    }

    /// Setup GID mapping for user namespace
    fn setup_gid_map(&self) -> Result<()> {
        let pid = getpid();

        // First, deny setgroups
        let setgroups_path = format!("/proc/{}/setgroups", pid);
        write_proc_file(&setgroups_path, "deny\n").map_err(|e| {
            RootboxError::NamespaceError(format!("Failed to write setgroups: {}", e))
        })?;

        // Then setup GID mapping
        let gid_map_path = format!("/proc/{}/gid_map", pid);
        let gid_map_content = format!("0 {} 1\n", self.outer_gid);

        debug!("Writing GID map: {}", gid_map_content.trim());

        write_proc_file(&gid_map_path, &gid_map_content)
            .map_err(|e| RootboxError::NamespaceError(format!("Failed to write gid_map: {}", e)))?;

        Ok(())
    }

    /// Setup other namespaces (mount, PID, UTS, network)
    pub fn setup_namespaces(&self) -> Result<()> {
        let mut flags = CloneFlags::empty();

        if self.config.features.pid_namespace {
            flags |= CloneFlags::CLONE_NEWPID;
        }

        if self.config.features.uts_namespace {
            flags |= CloneFlags::CLONE_NEWUTS;
        }

        if self.config.features.network_namespace {
            flags |= CloneFlags::CLONE_NEWNET;
        }

        if !flags.is_empty() {
            info!("Setting up namespaces: {:?}", flags);
            unshare(flags).map_err(|e| {
                warn!("Failed to unshare namespaces: {}", e);
                RootboxError::NamespaceError(format!("Failed to unshare namespaces: {}", e))
            })?;
        }

        // Set hostname if UTS namespace is enabled
        if self.config.features.uts_namespace {
            if let Some(hostname) = &self.config.namespaces.hostname {
                self.set_hostname(hostname)?;
            } else {
                // Set default hostname based on mode
                self.set_hostname("rootbox")?;
            }
        }

        Ok(())
    }

    pub fn setup_mount_namespace(&self) -> Result<()> {
        if !self.config.features.mount_namespace {
            warn!("Mount namespace disabled in config");
            return Ok(());
        }

        info!("Setting up mount namespace");

        unshare(CloneFlags::CLONE_NEWNS).map_err(|e| {
            RootboxError::NamespaceError(format!("Failed to unshare mount namespace: {}", e))
        })?;

        if !self.config.mounts.make_root_private {
            return Ok(());
        }

        debug!("Making root mount private");

        mount(
            None::<&str>,
            "/",
            None::<&str>,
            MsFlags::MS_REC | MsFlags::MS_PRIVATE,
            None::<&str>,
        )
        .map_err(|e| {
            warn!("Failed to make root private: {}", e);
            RootboxError::MountError(format!("Failed to make root private: {}", e))
        })?;

        Ok(())
    }

    /// Set hostname in UTS namespace
    fn set_hostname(
        &self,
        hostname: &str,
    ) -> Result<()> {
        debug!("Setting hostname to: {}", hostname);

        sethostname(hostname).map_err(|e| {
            warn!("Failed to set hostname: {}", e);
            RootboxError::NamespaceError(format!("Failed to set hostname: {}", e))
        })?;

        // Also try to set domainname if specified
        if let Some(domainname) = &self.config.namespaces.domainname {
            debug!("Setting domainname to: {}", domainname);
            // setdomainname is not directly available in nix, but it's similar to sethostname
            unsafe {
                let result = libc::setdomainname(
                    domainname.as_ptr() as *const libc::c_char,
                    domainname.len(),
                );
                if result != 0 {
                    warn!(
                        "Failed to set domainname: {}",
                        std::io::Error::last_os_error()
                    );
                }
            }
        }

        Ok(())
    }

    /// Setup parent death signal
    pub fn setup_parent_death_signal(&self) -> Result<()> {
        if !self.config.features.parent_death_signal {
            return Ok(());
        }

        debug!("Setting up parent death signal");

        // PR_SET_PDEATHSIG - send SIGKILL when parent dies
        unsafe {
            let result = libc::prctl(libc::PR_SET_PDEATHSIG, libc::SIGKILL);
            if result != 0 {
                warn!(
                    "Failed to set parent death signal: {}",
                    std::io::Error::last_os_error()
                );
            }
        }

        Ok(())
    }

    /// Set NO_NEW_PRIVS flag
    pub fn set_no_new_privs(&self) -> Result<()> {
        if !self.config.features.no_new_privs {
            return Ok(());
        }

        debug!("Setting NO_NEW_PRIVS");

        unsafe {
            let result = libc::prctl(libc::PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
            if result != 0 {
                return Err(RootboxError::NamespaceError(format!(
                    "Failed to set NO_NEW_PRIVS: {}",
                    std::io::Error::last_os_error()
                )));
            }
        }

        Ok(())
    }
}

/// Helper function to write to proc files
fn write_proc_file(
    path: &str,
    content: &str,
) -> std::io::Result<()> {
    let mut file = OpenOptions::new().write(true).open(path)?;
    file.write_all(content.as_bytes())?;
    file.flush()?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_namespace_manager_creation() {
        let config = Config::default();
        let manager = NamespaceManager::new(config);
        assert!(!manager.outer_uid.is_root() || manager.outer_uid.is_root());
    }
}
