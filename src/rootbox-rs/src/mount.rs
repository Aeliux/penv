use crate::config::{BindMount, Config};
use crate::error::{Result, RootboxError};
use nix::mount::{mount, MsFlags};
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

    /// Setup basic mounts (proc, sys, dev, tmp) inside the new root
    pub fn setup_basic_mounts(
        &self,
        new_root: &Path,
    ) -> Result<()> {
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
            )
            .map_err(|e| {
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
            )
            .map_err(|e| {
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
            )
            .map_err(|e| {
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
            )
            .map_err(|e| {
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
    fn setup_bind_mount(
        &self,
        new_root: &Path,
        bind_mount: &BindMount,
    ) -> Result<()> {
        let dest = new_root.join(
            bind_mount
                .destination
                .strip_prefix("/")
                .unwrap_or(&bind_mount.destination),
        );
        self.ensure_dir(&dest)?;

        debug!(
            "Bind mounting {} to {}",
            bind_mount.source.display(),
            dest.display()
        );

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
        )
        .map_err(|e| {
            warn!(
                "Failed to bind mount {}: {}",
                bind_mount.source.display(),
                e
            );
            RootboxError::MountError(format!("Failed to bind mount: {}", e))
        })?;

        Ok(())
    }

    /// Ensure directory exists
    fn ensure_dir(
        &self,
        path: &Path,
    ) -> Result<()> {
        if !path.exists() {
            fs::create_dir_all(path).map_err(|e| {
                RootboxError::MountError(format!(
                    "Failed to create directory {}: {}",
                    path.display(),
                    e
                ))
            })?;
        }
        Ok(())
    }

    /// Perform chroot to new root
    pub fn chroot(
        &self,
        new_root: &Path,
    ) -> Result<()> {
        info!("Chrooting to {}", new_root.display());

        chroot(new_root).map_err(|e| {
            RootboxError::ChrootError(format!("Failed to chroot to {}: {}", new_root.display(), e))
        })?;

        // Change directory to root after chroot
        std::env::set_current_dir("/")
            .map_err(|e| RootboxError::ChrootError(format!("Failed to chdir to /: {}", e)))?;

        Ok(())
    }
}

/// OverlayFS manager for handling overlayfs mounts
pub struct OverlayFsManager {
    image_path: PathBuf,
    extra_layers: Option<Vec<PathBuf>>,
    persist_path: Option<PathBuf>,
    temp_upper: Option<PathBuf>,
    temp_work: PathBuf,
    temp_merged: PathBuf,
}

impl OverlayFsManager {
    pub fn new(
        image_path: PathBuf,
        extra_layers: Option<Vec<PathBuf>>,
        persist_path: Option<PathBuf>,
    ) -> Self {
        let mut upper = None;
        if persist_path.is_none() {
            upper = Some(
                TempDir::new()
                    .expect("Failed to create temp upper dir")
                    .keep(),
            );
            info!(
                "Using temporary upper dir at {}",
                upper.as_ref().unwrap().display()
            );
        } else {
            info!(
                "Using persistent upper dir at {}",
                persist_path.as_ref().unwrap().display()
            );
        }

        let work = TempDir::new()
            .expect("Failed to create temp work dir")
            .keep();
        let merged = TempDir::new()
            .expect("Failed to create temp merged dir")
            .keep();

        Self {
            image_path,
            extra_layers,
            persist_path,
            temp_upper: upper,
            temp_work: work,
            temp_merged: merged,
        }
    }

    pub fn get_final_root(&self) -> PathBuf {
        self.temp_merged.clone()
    }

    /// Setup overlayfs and return the merged path
    pub fn setup(&mut self) -> Result<()> {
        info!(
            "Setting up OverlayFS with image: {}",
            self.image_path.display()
        );

        let upper_path = if let Some(persist) = &self.persist_path {
            persist.clone()
        } else {
            self.temp_upper
                .as_ref()
                .expect("Temp upper dir should exist")
                .clone()
        };

        // Build lowerdir string
        let mut lower_dirs = vec![self.image_path.to_string_lossy().to_string()];
        if let Some(extra_layers) = &self.extra_layers {
            for layer in extra_layers {
                lower_dirs.push(layer.to_string_lossy().to_string());
            }
        }
        // Reverse to have the correct order
        lower_dirs.reverse();

        let lower_string = lower_dirs.join(":");

        // Build overlayfs mount options
        let options = format!(
            "lowerdir={},upperdir={},workdir={}",
            lower_string,
            upper_path.display(),
            self.temp_work.display()
        );

        debug!("OverlayFS options: {}", options);

        // Mount overlayfs
        mount(
            Some("overlay"),
            &self.temp_merged,
            Some("overlay"),
            MsFlags::empty(),
            Some(options.as_str()),
        )
        .map_err(|e| RootboxError::OverlayFsError(format!("Failed to mount overlayfs: {}", e)))?;

        info!("OverlayFS mounted at: {}", self.temp_merged.display());

        Ok(())
    }

    pub fn cleanup(&self) -> Result<()> {
        info!("Cleaning up OverlayFS");

        // Remove temporary directories

        if let Some(upper) = &self.temp_upper {
            debug!("Removing temp upper dir at {}", upper.display());
            fs::remove_dir_all(upper).map_err(|e| {
                RootboxError::OverlayFsError(format!(
                    "Failed to remove temp upper dir {}: {}",
                    upper.display(),
                    e
                ))
            })?;
        }

        debug!("Removing temp work dir at {}", self.temp_work.display());
        fs::remove_dir_all(&self.temp_work).map_err(|e| {
            RootboxError::OverlayFsError(format!(
                "Failed to remove temp work dir {}: {}",
                self.temp_work.display(),
                e
            ))
        })?;

        debug!("Removing temp mount dir at {}", self.temp_merged.display());
        fs::remove_dir_all(&self.temp_merged).map_err(|e| {
            RootboxError::OverlayFsError(format!(
                "Failed to remove temp merged dir {}: {}",
                self.temp_merged.display(),
                e
            ))
        })?;

        Ok(())
    }
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
}
