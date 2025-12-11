use crate::config::{Config, BindMount};
use crate::error::{Result, RootboxError};
use nix::mount::{mount, umount2, MsFlags, MntFlags};
use nix::unistd::chroot;
use std::fs;
use std::path::{Path, PathBuf};
use tempfile::TempDir;
use tracing::{debug, info, warn};

/// Mount manager for handling filesystem operations
pub struct MountManager {
    config: Config,
}

impl MountManager {
    pub fn new(config: Config) -> Self {
        Self { config }
    }
    
    /// Make root mount private
    pub fn make_root_private(&self) -> Result<()> {
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
        ).map_err(|e| {
            warn!("Failed to make root private: {}", e);
            RootboxError::MountError(format!("Failed to make root private: {}", e))
        })?;
        
        Ok(())
    }
    
    /// Setup basic mounts (proc, sys, dev, tmp) inside the new root
    pub fn setup_basic_mounts(&self, new_root: &Path) -> Result<()> {
        info!("Setting up basic mounts in {}", new_root.display());
        
        // Mount /proc
        if self.config.mounts.mount_proc {
            let proc_dir = new_root.join("proc");
            self.ensure_dir(&proc_dir)?;
            
            debug!("Mounting proc at {}", proc_dir.display());
            mount(
                Some("proc"),
                &proc_dir,
                Some("proc"),
                MsFlags::empty(),
                None::<&str>,
            ).map_err(|e| {
                warn!("Failed to mount proc: {}", e);
                RootboxError::MountError(format!("Failed to mount proc: {}", e))
            })?;
        }
        
        // Mount /sys
        if self.config.mounts.mount_sys {
            let sys_dir = new_root.join("sys");
            self.ensure_dir(&sys_dir)?;
            
            debug!("Mounting sys at {}", sys_dir.display());
            let mut sys_flags = MsFlags::MS_BIND | MsFlags::MS_REC;
            if self.config.mounts.sys_readonly {
                sys_flags |= MsFlags::MS_RDONLY;
            }
            
            // Bind mount /sys since sysfs may not work in user namespace
            mount(
                Some("/sys"),
                &sys_dir,
                None::<&str>,
                sys_flags,
                None::<&str>,
            ).map_err(|e| {
                warn!("Failed to mount sys: {}", e);
                RootboxError::MountError(format!("Failed to mount sys: {}", e))
            })?;
        }
        
        // Mount /dev
        if self.config.mounts.mount_dev {
            let dev_dir = new_root.join("dev");
            self.ensure_dir(&dev_dir)?;
            
            debug!("Mounting dev at {}", dev_dir.display());
            mount(
                Some("/dev"),
                &dev_dir,
                None::<&str>,
                MsFlags::MS_BIND | MsFlags::MS_REC,
                None::<&str>,
            ).map_err(|e| {
                warn!("Failed to mount dev: {}", e);
                RootboxError::MountError(format!("Failed to mount dev: {}", e))
            })?;
        }
        
        // Mount /tmp as tmpfs
        if self.config.mounts.mount_tmp {
            let tmp_dir = new_root.join("tmp");
            self.ensure_dir(&tmp_dir)?;
            
            debug!("Mounting tmpfs at {}", tmp_dir.display());
            mount(
                Some("tmpfs"),
                &tmp_dir,
                Some("tmpfs"),
                MsFlags::empty(),
                None::<&str>,
            ).map_err(|e| {
                warn!("Failed to mount tmpfs: {}", e);
                RootboxError::MountError(format!("Failed to mount tmpfs: {}", e))
            })?;
        }
        
        // Setup additional bind mounts
        for bind_mount in &self.config.mounts.bind_mounts {
            self.setup_bind_mount(new_root, bind_mount)?;
        }
        
        Ok(())
    }
    
    /// Setup a single bind mount
    fn setup_bind_mount(&self, new_root: &Path, bind_mount: &BindMount) -> Result<()> {
        let dest = new_root.join(bind_mount.destination.strip_prefix("/").unwrap_or(&bind_mount.destination));
        self.ensure_dir(&dest)?;
        
        debug!("Bind mounting {} to {}", bind_mount.source.display(), dest.display());
        
        let mut flags = MsFlags::MS_BIND;
        if bind_mount.recursive {
            flags |= MsFlags::MS_REC;
        }
        if bind_mount.readonly {
            flags |= MsFlags::MS_RDONLY;
        }
        
        mount(
            Some(&bind_mount.source),
            &dest,
            None::<&str>,
            flags,
            None::<&str>,
        ).map_err(|e| {
            warn!("Failed to bind mount {}: {}", bind_mount.source.display(), e);
            RootboxError::MountError(format!("Failed to bind mount: {}", e))
        })?;
        
        Ok(())
    }
    
    /// Ensure directory exists
    fn ensure_dir(&self, path: &Path) -> Result<()> {
        if !path.exists() {
            fs::create_dir_all(path)
                .map_err(|e| RootboxError::MountError(
                    format!("Failed to create directory {}: {}", path.display(), e)
                ))?;
        }
        Ok(())
    }
    
    /// Perform chroot to new root
    pub fn chroot(&self, new_root: &Path) -> Result<()> {
        info!("Chrooting to {}", new_root.display());
        
        chroot(new_root)
            .map_err(|e| RootboxError::ChrootError(
                format!("Failed to chroot to {}: {}", new_root.display(), e)
            ))?;
        
        // Change directory to root after chroot
        std::env::set_current_dir("/")
            .map_err(|e| RootboxError::ChrootError(
                format!("Failed to chdir to /: {}", e)
            ))?;
        
        Ok(())
    }
}

/// OverlayFS manager for handling overlayfs mounts
pub struct OverlayFsManager {
    image_path: PathBuf,
    persist_path: Option<PathBuf>,
    temp_dirs: Vec<TempDir>,
}

impl OverlayFsManager {
    pub fn new(image_path: PathBuf, persist_path: Option<PathBuf>) -> Self {
        Self {
            image_path,
            persist_path,
            temp_dirs: Vec::new(),
        }
    }
    
    /// Setup overlayfs and return the merged path
    pub fn setup(&mut self) -> Result<PathBuf> {
        info!("Setting up OverlayFS with image: {}", self.image_path.display());
        
        // Create temporary directories
        let merged_dir = TempDir::new()
            .map_err(|e| RootboxError::OverlayFsError(
                format!("Failed to create merged directory: {}", e)
            ))?;
        
        let work_dir = TempDir::new()
            .map_err(|e| RootboxError::OverlayFsError(
                format!("Failed to create work directory: {}", e)
            ))?;
        
        let merged_path = merged_dir.path().to_path_buf();
        let work_path = work_dir.path().to_path_buf();
        
        // Determine upper directory
        let (upper_path, _upper_is_temp) = match &self.persist_path {
            Some(persist) => {
                info!("Using persistent overlay at: {}", persist.display());
                // Create persist directory if it doesn't exist
                fs::create_dir_all(persist)
                    .map_err(|e| RootboxError::OverlayFsError(
                        format!("Failed to create persist directory: {}", e)
                    ))?;
                (persist.clone(), false)
            }
            None => {
                info!("Using ephemeral overlay");
                let upper_dir = TempDir::new()
                    .map_err(|e| RootboxError::OverlayFsError(
                        format!("Failed to create upper directory: {}", e)
                    ))?;
                let upper_path = upper_dir.path().to_path_buf();
                self.temp_dirs.push(upper_dir);
                (upper_path, true)
            }
        };
        
        // Build overlayfs mount options
        let options = format!(
            "lowerdir={},upperdir={},workdir={}",
            self.image_path.display(),
            upper_path.display(),
            work_path.display()
        );
        
        debug!("OverlayFS options: {}", options);
        
        // Mount overlayfs
        mount(
            Some("overlay"),
            &merged_path,
            Some("overlay"),
            MsFlags::empty(),
            Some(options.as_str()),
        ).map_err(|e| RootboxError::OverlayFsError(
            format!("Failed to mount overlayfs: {}", e)
        ))?;
        
        info!("OverlayFS mounted at: {}", merged_path.display());
        
        // Store temp directories so they don't get dropped
        self.temp_dirs.push(merged_dir);
        self.temp_dirs.push(work_dir);
        
        Ok(merged_path)
    }
    
    /// Cleanup overlayfs mount
    pub fn cleanup(&mut self, merged_path: &Path) -> Result<()> {
        debug!("Cleaning up OverlayFS at {}", merged_path.display());
        
        // Unmount overlayfs
        if let Err(e) = umount2(merged_path, MntFlags::MNT_DETACH) {
            warn!("Failed to unmount overlayfs: {}", e);
        }
        
        // Temp directories will be automatically cleaned up when dropped
        self.temp_dirs.clear();
        
        Ok(())
    }
}

/// Utility function to recursively create directories
pub fn mkdir_p(path: &Path) -> Result<()> {
    fs::create_dir_all(path)
        .map_err(|e| RootboxError::MountError(
            format!("Failed to create directory {}: {}", path.display(), e)
        ))
}

#[cfg(test)]
mod tests {
    use super::*;
    
    #[test]
    fn test_mount_manager_creation() {
        let config = Config::default();
        let manager = MountManager::new(config);
        assert!(manager.config.mounts.mount_proc);
    }
    
    #[test]
    fn test_mkdir_p() {
        let temp_dir = TempDir::new().unwrap();
        let nested_path = temp_dir.path().join("a/b/c/d");
        mkdir_p(&nested_path).unwrap();
        assert!(nested_path.exists());
    }
}
