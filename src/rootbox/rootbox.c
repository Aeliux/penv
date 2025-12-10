/* rootbox.c - Isolated chroot using user namespaces */
#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <errno.h>
#include <sched.h>
#include <sys/prctl.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <sys/ioctl.h>
#include <sys/sysmacros.h>
#include <termios.h>
#include <signal.h>
#include <limits.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <sys/types.h>
#include <pty.h>

extern char **environ;

static void fatal(const char *msg) {
    fprintf(stderr, "rootbox: %s: %s\n", msg, strerror(errno));
    exit(1);
}

static void usage(void) {
    fprintf(stderr, "usage: rootbox <newRoot> <cmdPath> <cmdArgs...>\n");
    exit(2);
}

static void make_mount_private(void) {
    if (mount("", "/", "", MS_REC | MS_PRIVATE, "") < 0) {
        fprintf(stderr, "warning: mount --make-rprivate failed: %s\n", strerror(errno));
    }
}

static void restore_tty(int fd, struct termios *saved) {
    if (isatty(fd)) {
        tcsetattr(fd, TCSANOW, saved);
    }
}

static int setup_pty(int *master_fd, int *slave_fd) {
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

static void io_loop(int master_fd, pid_t child_pid) {
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

static void mkdirp(const char *path) {
    char tmp[PATH_MAX], *p;
    snprintf(tmp, sizeof(tmp), "%s", path);
    size_t len = strlen(tmp);
    if (tmp[len - 1] == '/') tmp[len - 1] = 0;
    for (p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            mkdir(tmp, 0755);
            *p = '/';
        }
    }
    mkdir(tmp, 0755);
}

static void write_file(const char *path, const char *content) {
    int fd = open(path, O_WRONLY);
    if (fd < 0) {
        fprintf(stderr, "warning: failed to open %s: %s\n", path, strerror(errno));
        return;
    }
    size_t len = strlen(content);
    ssize_t written = write(fd, content, len);
    if (written != (ssize_t)len) {
        fprintf(stderr, "warning: failed to write to %s: %s\n", path, strerror(errno));
    }
    close(fd);
}

static void setup_uid_map(pid_t pid, uid_t outer_uid) {
    char path[256], map[256];
    snprintf(path, sizeof(path), "/proc/%d/uid_map", pid);
    /* Map current user to root inside namespace (standard approach) */
    snprintf(map, sizeof(map), "0 %d 1\n", outer_uid);
    write_file(path, map);
}

static void setup_gid_map(pid_t pid, gid_t outer_gid) {
    char path[256], map[256];
    snprintf(path, sizeof(path), "/proc/%d/setgroups", pid);
    write_file(path, "deny\n");
    snprintf(path, sizeof(path), "/proc/%d/gid_map", pid);
    /* Map current group to root inside namespace (standard approach) */
    snprintf(map, sizeof(map), "0 %d 1\n", outer_gid);
    write_file(path, map);
}

static void setup_user_namespace(uid_t outer_uid, gid_t outer_gid) {
    if (unshare(CLONE_NEWUSER) < 0) fatal("unshare(CLONE_NEWUSER) failed");
    setup_uid_map(getpid(), outer_uid);
    setup_gid_map(getpid(), outer_gid);
}

int main(int argc, char **argv) {
    char *new_root, *cmd_path, new_root_abs[PATH_MAX];
    char proc_dir[PATH_MAX], sys_dir[PATH_MAX], dev_dir[PATH_MAX], tmp_dir[PATH_MAX];
    char devpts_dir[PATH_MAX];
    uid_t original_uid = getuid();
    gid_t original_gid = getgid();
    int master_fd = -1, slave_fd = -1;
    struct termios saved_tio;
    int saved_tty = 0;
    
    if (argc < 3) usage();
    new_root = argv[1];
    cmd_path = argv[2];
    
    if (realpath(new_root, new_root_abs) == NULL) fatal("realpath failed");

    if (snprintf(proc_dir, sizeof(proc_dir), "%s/proc", new_root_abs) >= (int)sizeof(proc_dir))
        fatal("path too long");
    if (snprintf(sys_dir, sizeof(sys_dir), "%s/sys", new_root_abs) >= (int)sizeof(sys_dir))
        fatal("path too long");
    if (snprintf(dev_dir, sizeof(dev_dir), "%s/dev", new_root_abs) >= (int)sizeof(dev_dir))
        fatal("path too long");
    if (snprintf(tmp_dir, sizeof(tmp_dir), "%s/tmp", new_root_abs) >= (int)sizeof(tmp_dir))
        fatal("path too long");
    if (snprintf(devpts_dir, sizeof(devpts_dir), "%s/dev/pts", new_root_abs) >= (int)sizeof(devpts_dir))
        fatal("path too long");

    /* Save original terminal settings */
    if (isatty(STDIN_FILENO)) {
        if (tcgetattr(STDIN_FILENO, &saved_tio) == 0) {
            saved_tty = 1;
        }
    }

    /* Set up PTY pair */
    if (setup_pty(&master_fd, &slave_fd) < 0) {
        fatal("failed to create PTY");
    }

    if (prctl(PR_SET_PDEATHSIG, SIGKILL) < 0) {
        fprintf(stderr, "warning: PR_SET_PDEATHSIG failed: %s\n", strerror(errno));
    }
    
    /* Try to create user namespace if we're not already root */
    if (geteuid() != 0) {
        setup_user_namespace(original_uid, original_gid);
    }
    
    /* Unshare mount, PID and uts namespaces */
    if (unshare(CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWUTS) < 0) {
        fprintf(stderr, "warning: unshare failed: %s\n", strerror(errno));
    }

    /* set host and domain names*/
    if (sethostname("rootbox", 7) < 0) {
        fprintf(stderr, "warning: sethostname failed: %s\n", strerror(errno));
    }
    if (setdomainname("rootbox", 7) < 0) {
        fprintf(stderr, "warning: setdomainname failed: %s\n", strerror(errno));
    }
    
    /* Fork - child becomes PID 1 */
    pid_t pid = fork();
    if (pid < 0) fatal("fork failed");
    if (pid > 0) {
        /* Parent process */
        close(slave_fd);
        
        /* Put our terminal in raw mode for proper forwarding */
        if (isatty(STDIN_FILENO)) {
            struct termios raw = saved_tio;
            cfmakeraw(&raw);
            tcsetattr(STDIN_FILENO, TCSANOW, &raw);
        }
        
        /* Handle I/O between terminal and PTY */
        io_loop(master_fd, pid);
        
        /* Wait for child */
        int status;
        waitpid(pid, &status, 0);
        
        /* Restore terminal */
        close(master_fd);
        if (saved_tty) {
            restore_tty(STDIN_FILENO, &saved_tio);
        }
        
        exit(WIFEXITED(status) ? WEXITSTATUS(status) : 1);
    }
    
    /* Child (PID 1) continues */
    close(master_fd);
    
    make_mount_private();
    
    /* Create necessary directories */
    mkdirp(proc_dir);
    mkdirp(sys_dir);
    mkdirp(dev_dir);
    mkdirp(tmp_dir);
    
    /* Bind mount /dev for access to system devpts */
    mount("/dev", dev_dir, "", MS_BIND | MS_REC, "");
    mount("proc", proc_dir, "proc", 0, "");
    mount("sysfs", sys_dir, "sysfs", 0, "");
    mount("tmpfs", tmp_dir, "tmpfs", 0, "");
    
    if (chroot(new_root_abs) < 0) fatal("chroot failed");
    if (chdir("/") < 0) fatal("chdir failed");
    
    /* Become session leader */
    if (setsid() < 0) {
        fprintf(stderr, "warning: setsid failed: %s\n", strerror(errno));
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
        fprintf(stderr, "warning: TIOCSCTTY failed: %s\n", strerror(errno));
    }

    /* Disable setuid/setgid binaries inside the chroot for security */
    prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);

    execve(cmd_path, argv + 2, environ);
    fatal("execve failed");
}
