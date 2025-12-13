mod config;
mod error;
mod mount;
mod namespace;
mod pty;

use clap::{Parser, Subcommand};
#[cfg(feature = "shell-completion")]
use clap::CommandFactory;
use config::Config;
use error::{Result, RootboxError};
use mount::{MountManager, OverlayFsManager};
use namespace::NamespaceManager;
use nix::sys::wait::waitpid;
use nix::unistd::{fork, ForkResult};
use pty::PtyManager;
use std::ffi::CString;
use std::path::PathBuf;
use log::{error, info, LevelFilter};

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
    #[cfg(feature = "shell-completion")]
    Completion {
        /// Shell type (bash, zsh, fish, powershell, elvish)
        #[arg(value_name = "SHELL")]
        shell: String,
    },
}

/// Simple logger with CRLF conversion and color support
struct SimpleLogger {
    use_color: bool,
    max_length: u8,
}

impl SimpleLogger {
    fn new(use_color: bool) -> Self {
        SimpleLogger {
            use_color,
            max_length: 10,
        }
    }
}

impl log::Log for SimpleLogger {
    fn enabled(&self, _metadata: &log::Metadata) -> bool {
        true
    }

    fn log(&self, record: &log::Record) {
        if self.enabled(record.metadata()) {
            use std::io::Write;
            
            let level_color = if self.use_color {
                match record.level() {
                    log::Level::Error => "\x1b[31m",  // Red
                    log::Level::Warn => "\x1b[33m",   // Yellow
                    log::Level::Info => "\x1b[32m",   // Green
                    log::Level::Debug => "\x1b[36m",  // Cyan
                    log::Level::Trace => "\x1b[35m",  // Magenta
                }
            } else {
                ""
            };
            let reset = if self.use_color { "\x1b[0m" } else { "" };

            let max_length = self.max_length as usize;
            
            // Write with CRLF line endings
            let _ = writeln!(
                std::io::stderr(),
                "{}{:<max_length$}{} {}\r",
                level_color,
                format!("[{}({})]", record.level(), if std::process::id() == 1 { "C" } else { "P" }),
                reset,
                record.args()
            );
        }
    }

    fn flush(&self) {}
}

fn main() {
    if let Err(e) = run() {
        error!("Error: {}", e);
        std::process::exit(1);
    }
}

fn run() -> anyhow::Result<()> {
    let cli = Cli::parse();

    // Setup simple logger with CRLF writer and colors for TTY
    let log_level = if cli.verbose {
        LevelFilter::Debug
    } else {
        std::env::var("RUST_LOG")
            .ok()
            .and_then(|s| s.parse().ok())
            .unwrap_or(LevelFilter::Warn)
    };

    // Check if stderr is a TTY once at startup
    let use_color = unsafe { libc::isatty(libc::STDERR_FILENO) == 1 };
    
    // Simple logger with color support for TTY - bypass env_logger's pipe and use direct stderr
    log::set_boxed_logger(Box::new(SimpleLogger::new(use_color)))
        .map(|()| log::set_max_level(log_level))
        .expect("Failed to initialize logger");

    match cli.command {
        Commands::GenConfig { output } => {
            generate_config(&output)?;
        },
        #[cfg(feature = "shell-completion")]
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
