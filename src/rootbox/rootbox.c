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
#include <termios.h>
#include <signal.h>
#include <limits.h>
#include <sys/wait.h>
#include <fcntl.h>
#include <sys/types.h>

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

static void make_tty_sane(int fd) {
    struct termios tio;
    if (!isatty(fd)) return;
    if (tcgetattr(fd, &tio) < 0) return;
    tio.c_lflag |= (ICANON | ECHO);
    tio.c_iflag |= ISTRIP;
    tcsetattr(fd, TCSANOW, &tio);
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
    uid_t original_uid = getuid();
    gid_t original_gid = getgid();
    
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
        int status;
        waitpid(pid, &status, 0);
        exit(WIFEXITED(status) ? WEXITSTATUS(status) : 1);
    }
    
    /* Child (PID 1) continues */
    make_mount_private();
    
    /* Create necessary directories */
    mkdirp(proc_dir);
    mkdirp(sys_dir);
    mkdirp(dev_dir);
    mkdirp(tmp_dir);
    
    mount("/dev", dev_dir, "", MS_BIND | MS_REC, "");
    mount("proc", proc_dir, "proc", 0, "");
    mount("sysfs", sys_dir, "sysfs", 0, "");
    mount("tmpfs", tmp_dir, "tmpfs", 0, "");
    
    if (chroot(new_root_abs) < 0) fatal("chroot failed");
    if (chdir("/") < 0) fatal("chdir failed");
    make_tty_sane(STDIN_FILENO);
    execve(cmd_path, argv + 2, environ);
    fatal("execve failed");
}
