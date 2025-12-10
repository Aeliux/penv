/* pty.c - PTY handling and I/O */
#include "rootbox.h"

void restore_tty(int fd, struct termios *saved) {
    if (isatty(fd)) {
        tcsetattr(fd, TCSANOW, saved);
    }
}

int setup_pty(int *master_fd, int *slave_fd) {
    char slave_name[PATH_MAX];
    struct termios tio;
    struct winsize ws;
    
    /* Get current terminal settings to copy them */
    int has_tty = isatty(STDIN_FILENO);
    if (has_tty) {
        if (tcgetattr(STDIN_FILENO, &tio) < 0) {
            fprintf(stderr, "warning: tcgetattr failed: %s\n", strerror(errno));
            has_tty = 0;
        }
        if (ioctl(STDIN_FILENO, TIOCGWINSZ, &ws) < 0) {
            fprintf(stderr, "warning: TIOCGWINSZ failed: %s\n", strerror(errno));
            ws.ws_row = 24;
            ws.ws_col = 80;
        }
    } else {
        /* Default terminal size */
        ws.ws_row = 24;
        ws.ws_col = 80;
    }
    
    /* Open PTY pair */
    if (openpty(master_fd, slave_fd, slave_name, has_tty ? &tio : NULL, &ws) < 0) {
        return -1;
    }
    
    return 0;
}

void setup_pty_slave(int slave_fd) {
    /* Become session leader */
    if (setsid() < 0) {
        fprintf(stderr, "warning: setsid failed: %s\r\n", strerror(errno));
    }
    
    /* Redirect stdio to the slave PTY */
    if (dup2(slave_fd, STDIN_FILENO) < 0) fatal("dup2 stdin failed");
    if (dup2(slave_fd, STDOUT_FILENO) < 0) fatal("dup2 stdout failed");
    if (dup2(slave_fd, STDERR_FILENO) < 0) fatal("dup2 stderr failed");
    
    if (slave_fd > STDERR_FILENO) {
        close(slave_fd);
    }
    
    /* Set controlling terminal */
    if (ioctl(STDIN_FILENO, TIOCSCTTY, 0) < 0) {
        fprintf(stderr, "warning: TIOCSCTTY failed: %s\r\n", strerror(errno));
    }
}

void io_loop(int master_fd, pid_t child_pid) {
    char buf[4096];
    fd_set readfds;
    int max_fd = (master_fd > STDIN_FILENO ? master_fd : STDIN_FILENO) + 1;
    
    while (1) {
        FD_ZERO(&readfds);
        FD_SET(STDIN_FILENO, &readfds);
        FD_SET(master_fd, &readfds);
        
        int ret = select(max_fd, &readfds, NULL, NULL, NULL);
        if (ret < 0) {
            if (errno == EINTR) continue;
            break;
        }
        
        /* Data from stdin -> pty master */
        if (FD_ISSET(STDIN_FILENO, &readfds)) {
            ssize_t n = read(STDIN_FILENO, buf, sizeof(buf));
            if (n <= 0) break;
            if (write(master_fd, buf, n) != n) break;
        }
        
        /* Data from pty master -> stdout */
        if (FD_ISSET(master_fd, &readfds)) {
            ssize_t n = read(master_fd, buf, sizeof(buf));
            if (n <= 0) break;
            if (write(STDOUT_FILENO, buf, n) != n) break;
        }
    }
}
