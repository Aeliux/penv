mod config;
mod error;
mod mount;
mod namespace;
mod pty;

use clap::{CommandFactory, Parser, Subcommand};
use config::Config;
use error::{Result, RootboxError};
use mount::{MountManager, OverlayFsManager};
use namespace::NamespaceManager;
use nix::sys::wait::waitpid;
use nix::unistd::{fork, ForkResult};
use pty::PtyManager;
use std::ffi::CString;
use std::io::Write;
use std::path::PathBuf;
use tracing::{error, info};
use tracing_subscriber::{fmt, EnvFilter};

#[derive(Parser)]
#[command(name = "rootbox")]
#[command(version, about = "Container-like isolation using Linux namespaces and overlayfs", long_about = None)]
struct Cli {
    /// Path to configuration file
    #[arg(short, long, value_name = "FILE")]
    config: Option<PathBuf>,

    /// Enable verbose logging
    #[arg(short, long)]
    verbose: bool,

    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// Enter and run command in a root directory (with chroot)
    Enter {
        /// Path to root directory
        #[arg(value_name = "ROOT_DIR")]
        root_dir: PathBuf,

        /// Command to execute
        #[arg(value_name = "COMMAND")]
        command: String,

        /// Command arguments
        #[arg(value_name = "ARGS", trailing_var_arg = true)]
        args: Vec<String>,
    },

    /// Run command with OverlayFS (ephemeral or persistent)
    Overlay {
        /// Path to root directory (lower layer)
        #[arg(value_name = "ROOT_DIR")]
        root_dir: PathBuf,

        /// Extra layers for lowerdir (multiple allowed, ordered)
        #[arg(short, long, value_name = "EXTRA_LAYERS")]
        extra_layers: Option<Vec<PathBuf>>,

        /// Path to persistence directory (optional, upper layer)
        #[arg(short, long, value_name = "PERSIST_DIR")]
        persist: Option<PathBuf>,

        /// Command to execute
        #[arg(value_name = "COMMAND")]
        command: String,

        /// Command arguments
        #[arg(value_name = "ARGS", trailing_var_arg = true)]
        args: Vec<String>,
    },

    /// Generate example configuration file
    GenConfig {
        /// Output file path
        #[arg(value_name = "OUTPUT", default_value = "rootbox.toml")]
        output: PathBuf,
    },
    Completion {
        /// Shell type (bash, zsh, fish, powershell, elvish)
        #[arg(value_name = "SHELL")]
        shell: String,
    },
}

/// Custom log writer that converts LF to CRLF
/// This ensures logs display correctly even when terminal is in raw mode
struct CrlfWriter<W> {
    inner: W,
}

impl<W: std::io::Write> std::io::Write for CrlfWriter<W> {
    fn write(
        &mut self,
        buf: &[u8],
    ) -> std::io::Result<usize> {
        // Convert LF to CRLF
        let mut output = Vec::with_capacity(buf.len());
        for &byte in buf {
            if byte == b'\n' {
                output.push(b'\r');
                output.push(b'\n');
            } else {
                output.push(byte);
            }
        }
        self.inner.write_all(&output)?;
        Ok(buf.len()) // Return original length
    }

    fn flush(&mut self) -> std::io::Result<()> {
        self.inner.flush()
    }
}

fn main() {
    if let Err(e) = run() {
        error!("Error: {}", e);
        std::process::exit(1);
    }
}

fn run() -> anyhow::Result<()> {
    let cli = Cli::parse();

    // Setup logging
    let filter = if cli.verbose {
        EnvFilter::new("debug")
    } else {
        EnvFilter::try_from_default_env().unwrap_or_else(|_| EnvFilter::new("warn"))
    };

    // Use custom writer that converts LF to CRLF
    // This ensures logs work correctly when terminal is in raw mode
    fmt()
        .with_env_filter(filter)
        .with_target(false)
        .with_writer(|| CrlfWriter {
            inner: std::io::stderr(),
        })
        .init();

    match cli.command {
        Commands::GenConfig { output } => {
            generate_config(&output)?;
        },
        Commands::Completion { shell } => {
            let mut cmd = Cli::command();
            let shell: clap_complete::Shell = shell.parse().map_err(|e| {
                RootboxError::ConfigError(format!("Invalid shell for completion: {}", e))
            })?;
            let mut buffer = Vec::new();
            clap_complete::generate(shell, &mut cmd, "rootbox", &mut buffer);
            std::io::stdout().write_all(&buffer)?;
        },
        Commands::Enter {
            root_dir,
            command,
            args,
        } => {
            let config = Config::load_or_default(cli.config.as_ref())?;
            run_enter(config, root_dir, command, args)?;
        },
        Commands::Overlay {
            root_dir,
            extra_layers,
            persist,
            command,
            args,
        } => {
            let config = Config::load_or_default(cli.config.as_ref())?;
            run_overlay(config, root_dir, extra_layers, persist, command, args)?;
        },
    }

    Ok(())
}

/// Generate example configuration file
fn generate_config(output: &PathBuf) -> anyhow::Result<()> {
    info!("Generating example configuration at: {}", output.display());

    let config = Config::default();
    config.to_file(output)?;

    println!("Configuration file created at: {}", output.display());
    Ok(())
}

/// Enter a root directory and run command (direct chroot, no overlayfs)
fn run_enter(
    config: Config,
    root_dir: PathBuf,
    command: String,
    args: Vec<String>,
) -> Result<()> {
    info!("Starting rootbox in enter mode");
    info!("Root directory: {}", root_dir.display());
    info!("Command: {} {:?}", command, args);

    // Verify root directory exists
    if !root_dir.exists() {
        return Err(RootboxError::PathError(format!(
            "Root directory does not exist: {}",
            root_dir.display()
        )));
    }

    run_container(config, root_dir, None, command, args)
}

/// Run in overlayfs mode
fn run_overlay(
    config: Config,
    root_dir: PathBuf,
    extra_layers: Option<Vec<PathBuf>>,
    persist: Option<PathBuf>,
    command: String,
    args: Vec<String>,
) -> Result<()> {
    let mode = if persist.is_some() {
        "persistent"
    } else {
        "ephemeral"
    };
    info!("Starting rootbox in overlayfs mode ({})", mode);
    info!("Root directory: {}", root_dir.display());
    if let Some(ref p) = persist {
        info!("Persist directory: {}", p.display());
    }
    info!("Command: {} {:?}", command, args);

    // Verify root directory exists
    if !root_dir.exists() {
        return Err(RootboxError::PathError(format!(
            "Root directory does not exist: {}",
            root_dir.display()
        )));
    }

    // Verify extra layers exist
    if let Some(ref layers) = extra_layers {
        for layer in layers {
            info!("Extra lowerdir layer: {}", layer.display());
            if !layer.exists() {
                return Err(RootboxError::PathError(format!(
                    "Extra lowerdir layer does not exist: {}",
                    layer.display()
                )));
            }
        }
    }

    // Create OverlayFS manager but don't setup yet (will be done in child after namespaces)
    let ofs_manager = OverlayFsManager::new(root_dir.clone(), extra_layers, persist);

    // Run container - overlayfs will be setup in child process
    run_container(
        config,
        ofs_manager.get_final_root(),
        Some(ofs_manager),
        command,
        args,
    )
}

/// Main container execution logic
fn run_container(
    config: Config,
    final_root: PathBuf,
    ofs_manager: Option<OverlayFsManager>,
    command: String,
    args: Vec<String>,
) -> Result<()> {
    // Setup PTY
    let mut pty_manager = PtyManager::new(config.clone());
    let (master_fd, slave_fd) = pty_manager.setup_pty()?;

    // Setup namespace manager
    let ns_manager = NamespaceManager::new(config.clone());

    // Setup parent death signal
    ns_manager.setup_parent_death_signal()?;

    // Setup user namespace if needed (must be done before other namespaces)
    ns_manager.setup_user_namespace()?;

    // Setup other namespaces
    ns_manager.setup_namespaces()?;

    // Setup mount manager
    let mount_manager = MountManager::new(config.clone());

    // Fork to create child process (becomes PID 1 in PID namespace)
    match unsafe { fork() } {
        Ok(ForkResult::Parent { child }) => {
            // Parent process
            info!("Forked child process: {}", child);

            // Close slave fd
            nix::unistd::close(slave_fd).ok();

            // Set terminal to raw mode
            pty_manager.set_raw_mode()?;

            // Run I/O loop (blocking)
            pty_manager.io_loop_blocking(master_fd, child)?;

            // Wait for child to exit
            info!("Waiting for child process to exit");
            let wait_status = waitpid(child, None).map_err(|e| {
                RootboxError::ProcessError(format!("Failed to wait for child: {}", e))
            })?;

            // Close master fd
            pty_manager.close()?;

            // Restore terminal
            pty_manager.restore_terminal()?;

            info!("Child exited with status: {:?}", wait_status);

            // Cleanup overlayfs if used
            if let Some(ofs) = ofs_manager {
                // Cleanup overlayfs temporary directories
                ofs.cleanup()?;
            }

            Ok(())
        },
        Ok(ForkResult::Child) => {
            // Child process (PID 1 in namespace)

            // Close master fd
            nix::unistd::close(master_fd).ok();

            // Setup mount namespace
            ns_manager.setup_mount_namespace()?;

            // Setup overlayfs if needed (MUST be done after namespaces, in child)
            if let Some(mut ofs) = ofs_manager {
                ofs.setup()?;
            };

            // Setup basic mounts
            mount_manager.setup_basic_mounts(&final_root)?;

            // Chroot into new root
            mount_manager.chroot(&final_root)?;

            // Setup slave PTY
            pty_manager.setup_slave(slave_fd)?;

            // Set NO_NEW_PRIVS
            ns_manager.set_no_new_privs()?;

            // Execute command
            execute_command(&command, &args)?;

            // Should not reach here
            unreachable!()
        },
        Err(e) => Err(RootboxError::ProcessError(format!("Fork failed: {}", e))),
    }
}

/// Execute the target command
fn execute_command(
    command: &str,
    args: &[String],
) -> Result<()> {
    info!("Executing: {} {:?}", command, args);

    // Build argument list
    let mut c_args: Vec<CString> = Vec::new();
    c_args.push(
        CString::new(command.as_bytes())
            .map_err(|e| RootboxError::ExecError(format!("Invalid command: {}", e)))?,
    );

    for arg in args {
        c_args.push(
            CString::new(arg.as_bytes())
                .map_err(|e| RootboxError::ExecError(format!("Invalid argument: {}", e)))?,
        );
    }

    // Execute
    nix::unistd::execvp(&c_args[0], &c_args)
        .map_err(|e| RootboxError::ExecError(format!("Failed to execute {}: {}", command, e)))?;

    unreachable!()
}
