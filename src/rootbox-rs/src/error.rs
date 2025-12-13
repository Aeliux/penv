use thiserror::Error;

/// Custom error types for rootbox operations
#[derive(Error, Debug)]
pub enum RootboxError {
    #[error("Failed to create namespace: {0}")]
    NamespaceError(String),

    #[error("Failed to setup mount: {0}")]
    MountError(String),

    #[error("Failed to setup overlayfs: {0}")]
    OverlayFsError(String),

    #[error("Failed to setup PTY: {0}")]
    PtyError(String),

    #[error("Failed to chroot: {0}")]
    ChrootError(String),

    #[error("Failed to execute command: {0}")]
    ExecError(String),

    #[error("I/O error: {0}")]
    IoError(#[from] std::io::Error),

    #[error("System call error: {0}")]
    SyscallError(#[from] nix::Error),

    #[error("Invalid path: {0}")]
    PathError(String),

    #[error("Process error: {0}")]
    ProcessError(String),
}

pub type Result<T> = std::result::Result<T, RootboxError>;
