use serde::{Deserialize, Serialize};
use std::path::PathBuf;

/// Main configuration structure for rootbox
#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// Features that can be toggled on/off
    pub features: Features,

    /// Namespace configuration
    pub namespaces: Namespaces,

    /// Mount configuration
    pub mounts: Mounts,

    /// Security settings
    pub security: Security,

    /// PTY configuration
    pub pty: Pty,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Features {
    /// Enable OverlayFS support
    pub overlayfs: bool,

    /// Enable user namespace
    pub user_namespace: bool,

    /// Enable mount namespace
    pub mount_namespace: bool,

    /// Enable PID namespace
    pub pid_namespace: bool,

    /// Enable UTS namespace (hostname isolation)
    pub uts_namespace: bool,

    /// Enable network namespace
    pub network_namespace: bool,

    /// Enable PTY allocation
    pub pty_enabled: bool,

    /// Enable death signal (SIGKILL on parent death)
    pub parent_death_signal: bool,

    /// Enable NO_NEW_PRIVS security flag
    pub no_new_privs: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Namespaces {
    /// Custom hostname for the container (if UTS namespace is enabled)
    pub hostname: Option<String>,

    /// Custom domain name for the container
    pub domainname: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Mounts {
    /// Mount /proc inside container
    pub mount_proc: bool,

    /// Mount /sys inside container
    pub mount_sys: bool,

    /// Mount /dev inside container
    pub mount_dev: bool,

    /// Mount /tmp as tmpfs inside container
    pub mount_tmp: bool,

    /// Make root mount private (MS_PRIVATE)
    pub make_root_private: bool,

    /// Mount /sys as read-only
    pub sys_readonly: bool,

    /// Additional bind mounts (source:destination pairs)
    pub bind_mounts: Vec<BindMount>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BindMount {
    /// Source path on host
    pub source: PathBuf,

    /// Destination path in container
    pub destination: PathBuf,

    /// Mount as read-only
    #[serde(default)]
    pub readonly: bool,

    /// Recursive bind mount
    #[serde(default = "default_true")]
    pub recursive: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Security {
    /// Enable AppArmor profile (if available)
    pub apparmor_enabled: bool,

    /// AppArmor profile name
    pub apparmor_profile: Option<String>,

    /// Drop all capabilities except specified ones
    pub drop_capabilities: bool,

    /// List of capabilities to keep (e.g., "CAP_NET_ADMIN")
    pub keep_capabilities: Vec<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Pty {
    /// Default terminal rows (if stdin is not a TTY)
    pub default_rows: u16,

    /// Default terminal columns (if stdin is not a TTY)
    pub default_cols: u16,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            features: Features::default(),
            namespaces: Namespaces::default(),
            mounts: Mounts::default(),
            security: Security::default(),
            pty: Pty::default(),
        }
    }
}

impl Default for Features {
    fn default() -> Self {
        Self {
            overlayfs: true,
            user_namespace: true,
            mount_namespace: true,
            pid_namespace: true,
            uts_namespace: true,
            network_namespace: false,
            pty_enabled: true,
            parent_death_signal: true,
            no_new_privs: true,
        }
    }
}

impl Default for Namespaces {
    fn default() -> Self {
        Self {
            hostname: None,
            domainname: None,
        }
    }
}

impl Default for Mounts {
    fn default() -> Self {
        Self {
            mount_proc: true,
            mount_sys: true,
            mount_dev: true,
            mount_tmp: true,
            make_root_private: true,
            sys_readonly: true,
            bind_mounts: vec![],
        }
    }
}

impl Default for Security {
    fn default() -> Self {
        Self {
            apparmor_enabled: false,
            apparmor_profile: None,
            drop_capabilities: false,
            keep_capabilities: vec![],
        }
    }
}

impl Default for Pty {
    fn default() -> Self {
        Self {
            default_rows: 24,
            default_cols: 80,
        }
    }
}

fn default_true() -> bool {
    true
}

impl Config {
    /// Load configuration from a TOML file
    pub fn from_file(path: &PathBuf) -> anyhow::Result<Self> {
        let content = std::fs::read_to_string(path)?;
        let config: Config = toml::from_str(&content)?;
        Ok(config)
    }

    /// Merge configuration from file with defaults
    pub fn load_or_default(path: Option<&PathBuf>) -> anyhow::Result<Self> {
        match path {
            Some(p) => Self::from_file(p),
            None => Ok(Self::default()),
        }
    }

    /// Save configuration to a TOML file
    pub fn to_file(
        &self,
        path: &PathBuf,
    ) -> anyhow::Result<()> {
        let content = toml::to_string_pretty(self)?;
        std::fs::write(path, content)?;
        Ok(())
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_default_config() {
        let config = Config::default();
        assert!(config.features.overlayfs);
        assert!(config.features.user_namespace);
        assert!(config.mounts.mount_proc);
    }

    #[test]
    fn test_config_serialization() {
        let config = Config::default();
        let toml_str = toml::to_string(&config).unwrap();
        let parsed: Config = toml::from_str(&toml_str).unwrap();
        assert!(parsed.features.overlayfs);
    }
}
