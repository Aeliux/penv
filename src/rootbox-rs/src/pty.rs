use crate::config::Config;
use crate::error::{Result, RootboxError};
use nix::libc::{winsize, TIOCGWINSZ, TIOCSCTTY};
use nix::pty::openpty;
use nix::sys::termios;
use nix::sys::termios::{tcgetattr, tcsetattr, SetArg, Termios};
use nix::unistd::{dup2, setsid, Pid};
use std::io::{self};
use std::os::unix::io::{AsRawFd, BorrowedFd, RawFd};
use tracing::{debug, warn};

/// PTY manager for pseudo-terminal handling
pub struct PtyManager {
    config: Config,
    master_fd: Option<RawFd>,
    slave_fd: Option<RawFd>,
    original_termios: Option<Termios>,
}

impl PtyManager {
    pub fn new(config: Config) -> Self {
        Self {
            config,
            master_fd: None,
            slave_fd: None,
            original_termios: None,
        }
    }

    /// Setup PTY pair
    pub fn setup_pty(&mut self) -> Result<(RawFd, RawFd)> {
        if !self.config.features.pty_enabled {
            return Err(RootboxError::PtyError("PTY disabled in config".to_string()));
        }

        debug!("Setting up PTY");

        // Get terminal attributes if stdin is a TTY
        let stdin_fd = std::io::stdin().as_raw_fd();
        let term_attrs = if nix::unistd::isatty(stdin_fd).unwrap_or(false) {
            match tcgetattr(unsafe { BorrowedFd::borrow_raw(stdin_fd) }) {
                Ok(attrs) => {
                    self.original_termios = Some(attrs.clone());
                    Some(attrs)
                },
                Err(e) => {
                    warn!("Failed to get terminal attributes: {}", e);
                    None
                },
            }
        } else {
            None
        };

        // Get window size
        let winsize = self.get_window_size(stdin_fd);

        // Open PTY
        let pty_result = openpty(&winsize, term_attrs.as_ref())
            .map_err(|e| RootboxError::PtyError(format!("Failed to open PTY: {}", e)))?;

        let master_raw = pty_result.master.as_raw_fd();
        let slave_raw = pty_result.slave.as_raw_fd();

        self.master_fd = Some(master_raw);
        self.slave_fd = Some(slave_raw);

        debug!("PTY created: master={}, slave={}", master_raw, slave_raw);

        // Keep the OwnedFd alive by leaking them (they'll be closed manually)
        std::mem::forget(pty_result.master);
        std::mem::forget(pty_result.slave);

        Ok((master_raw, slave_raw))
    }

    /// Get current window size or use defaults
    fn get_window_size(
        &self,
        fd: RawFd,
    ) -> winsize {
        let mut ws: winsize = unsafe { std::mem::zeroed() };

        if nix::unistd::isatty(fd).unwrap_or(false) {
            unsafe {
                if libc::ioctl(fd, TIOCGWINSZ, &mut ws) == 0 {
                    return ws;
                }
            }
        }

        // Use default size from config
        ws.ws_row = self.config.pty.default_rows;
        ws.ws_col = self.config.pty.default_cols;
        ws
    }

    /// Setup slave PTY in child process
    pub fn setup_slave(
        &self,
        slave_fd: RawFd,
    ) -> Result<()> {
        debug!("Setting up slave PTY");

        // Create new session
        setsid().map_err(|e| {
            warn!("Failed to create new session: {}", e);
            RootboxError::PtyError(format!("Failed to create session: {}", e))
        })?;

        // Redirect stdio to slave PTY
        dup2(slave_fd, libc::STDIN_FILENO)
            .map_err(|e| RootboxError::PtyError(format!("Failed to dup2 stdin: {}", e)))?;

        dup2(slave_fd, libc::STDOUT_FILENO)
            .map_err(|e| RootboxError::PtyError(format!("Failed to dup2 stdout: {}", e)))?;

        dup2(slave_fd, libc::STDERR_FILENO)
            .map_err(|e| RootboxError::PtyError(format!("Failed to dup2 stderr: {}", e)))?;

        // Close slave fd if it's greater than stderr
        if slave_fd > libc::STDERR_FILENO {
            nix::unistd::close(slave_fd)
                .map_err(|e| RootboxError::PtyError(format!("Failed to close slave fd: {}", e)))?;
        }

        // Set controlling terminal
        unsafe {
            if libc::ioctl(libc::STDIN_FILENO, TIOCSCTTY, 0) != 0 {
                warn!(
                    "Failed to set controlling terminal: {}",
                    io::Error::last_os_error()
                );
            }
        }

        Ok(())
    }

    /// Set terminal to raw mode
    pub fn set_raw_mode(&self) -> Result<()> {
        let stdin_fd = std::io::stdin().as_raw_fd();

        if !nix::unistd::isatty(stdin_fd).unwrap_or(false) {
            return Ok(());
        }

        debug!("Setting terminal to raw mode");

        let mut termios = tcgetattr(unsafe { BorrowedFd::borrow_raw(stdin_fd) }).map_err(|e| {
            RootboxError::PtyError(format!("Failed to get terminal attributes: {}", e))
        })?;

        termios::cfmakeraw(&mut termios);

        tcsetattr(
            unsafe { BorrowedFd::borrow_raw(stdin_fd) },
            SetArg::TCSANOW,
            &termios,
        )
        .map_err(|e| RootboxError::PtyError(format!("Failed to set raw mode: {}", e)))?;

        Ok(())
    }

    /// Restore original terminal settings
    pub fn restore_terminal(&self) -> Result<()> {
        if let Some(ref termios) = self.original_termios {
            let stdin_fd = std::io::stdin().as_raw_fd();

            if nix::unistd::isatty(stdin_fd).unwrap_or(false) {
                debug!("Restoring terminal settings");

                tcsetattr(
                    unsafe { BorrowedFd::borrow_raw(stdin_fd) },
                    SetArg::TCSANOW,
                    termios,
                )
                .map_err(|e| {
                    warn!("Failed to restore terminal: {}", e);
                    RootboxError::PtyError(format!("Failed to restore terminal: {}", e))
                })?;
            }
        }

        Ok(())
    }

    /// Run I/O loop between master PTY and stdin/stdout (blocking version)
    pub fn io_loop_blocking(
        &self,
        master_fd: RawFd,
        _child_pid: Pid,
    ) -> Result<()> {
        use nix::sys::select::{select, FdSet};

        debug!("Starting I/O loop");

        let stdin_fd = std::io::stdin().as_raw_fd();
        let stdout_fd = std::io::stdout().as_raw_fd();
        let max_fd = std::cmp::max(stdin_fd, master_fd) + 1;

        let mut buf = [0u8; 4096];

        loop {
            let mut readfds = FdSet::new();
            // Safety: these file descriptors are valid
            unsafe {
                readfds.insert(BorrowedFd::borrow_raw(stdin_fd));
                readfds.insert(BorrowedFd::borrow_raw(master_fd));
            }

            // Use select to wait for data
            match select(max_fd, Some(&mut readfds), None, None, None) {
                Ok(_) => {},
                Err(nix::errno::Errno::EINTR) => continue,
                Err(e) => {
                    warn!("select failed: {}", e);
                    break;
                },
            }

            // Data from stdin -> pty master
            if unsafe { readfds.contains(BorrowedFd::borrow_raw(stdin_fd)) } {
                match nix::unistd::read(stdin_fd, &mut buf) {
                    Ok(0) => break, // EOF
                    Ok(n) => {
                        // Write to master using raw syscall
                        let written = unsafe {
                            libc::write(master_fd, buf[..n].as_ptr() as *const libc::c_void, n)
                        };
                        if written != n as isize {
                            warn!("Failed to write to master");
                            break;
                        }
                    },
                    Err(e) => {
                        warn!("Failed to read from stdin: {}", e);
                        break;
                    },
                }
            }

            // Data from pty master -> stdout
            if unsafe { readfds.contains(BorrowedFd::borrow_raw(master_fd)) } {
                match nix::unistd::read(master_fd, &mut buf) {
                    Ok(0) => break, // EOF
                    Ok(n) => {
                        // Write to stdout using raw syscall
                        let written = unsafe {
                            libc::write(stdout_fd, buf[..n].as_ptr() as *const libc::c_void, n)
                        };
                        if written != n as isize {
                            warn!("Failed to write to stdout");
                            break;
                        }
                    },
                    Err(nix::errno::Errno::EIO) => {
                        // EIO means the child process has exited - this is normal
                        break;
                    },
                    Err(e) => {
                        warn!("Failed to read from master: {}", e);
                        break;
                    },
                }
            }
        }

        debug!("I/O loop ended");
        Ok(())
    }

    /// Close master and slave file descriptors
    pub fn close(&mut self) -> Result<()> {
        if let Some(master) = self.master_fd.take() {
            let _ = nix::unistd::close(master);
        }

        if let Some(slave) = self.slave_fd.take() {
            let _ = nix::unistd::close(slave);
        }

        Ok(())
    }
}

impl Drop for PtyManager {
    fn drop(&mut self) {
        let _ = self.close();
        let _ = self.restore_terminal();
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_pty_manager_creation() {
        let config = Config::default();
        let manager = PtyManager::new(config);
        assert!(manager.master_fd.is_none());
    }
}
