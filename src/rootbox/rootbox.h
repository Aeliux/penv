/* rootbox.h - Common definitions and includes */
#ifndef ROOTBOX_H
#define ROOTBOX_H

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
#include <dirent.h>

/* Common structures */
typedef struct {
    char *image_path;
    char *persist_path;
    char *cmd_path;
    char **cmd_args;
    int is_ofs_mode;
} rootbox_args_t;

/* Function declarations from other modules */
/* utils.c */
void fatal(const char *msg);
void mkdirp(const char *path);
void write_file(const char *path, const char *content);
int remove_dir_recursive(const char *path);

/* namespace.c */
void setup_user_namespace(uid_t outer_uid, gid_t outer_gid);
void setup_uid_map(pid_t pid, uid_t outer_uid);
void setup_gid_map(pid_t pid, gid_t outer_gid);

/* mount.c */
void make_mount_private(void);
void setup_basic_mounts(const char *new_root_abs);

/* pty.c */
int setup_pty(int *master_fd, int *slave_fd);
void setup_pty_slave(int slave_fd);
void io_loop(int master_fd, pid_t child_pid);
void restore_tty(int fd, struct termios *saved);

/* overlayfs.c */
char *setup_overlayfs(const char *image_path, const char *persist_path);
void cleanup_overlayfs(const char *merged_path);

#endif /* ROOTBOX_H */
