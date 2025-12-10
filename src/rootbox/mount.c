/* mount.c - Mount operations */
#include "rootbox.h"

void make_mount_private(void) {
    if (mount("", "/", "", MS_REC | MS_PRIVATE, "") < 0) {
        fprintf(stderr, "warning: mount --make-rprivate failed: %s\n", strerror(errno));
    }
}

void setup_basic_mounts(const char *new_root_abs) {
    char proc_dir[PATH_MAX], sys_dir[PATH_MAX], dev_dir[PATH_MAX], tmp_dir[PATH_MAX];
    
    if (snprintf(proc_dir, sizeof(proc_dir), "%s/proc", new_root_abs) >= (int)sizeof(proc_dir))
        fatal("path too long");
    if (snprintf(sys_dir, sizeof(sys_dir), "%s/sys", new_root_abs) >= (int)sizeof(sys_dir))
        fatal("path too long");
    if (snprintf(dev_dir, sizeof(dev_dir), "%s/dev", new_root_abs) >= (int)sizeof(dev_dir))
        fatal("path too long");
    if (snprintf(tmp_dir, sizeof(tmp_dir), "%s/tmp", new_root_abs) >= (int)sizeof(tmp_dir))
        fatal("path too long");
    
    /* Create necessary directories */
    mkdirp(proc_dir);
    mkdirp(sys_dir);
    mkdirp(dev_dir);
    mkdirp(tmp_dir);
    
    /* Bind mount /dev for access to system devpts */
    if (mount("/dev", dev_dir, "", MS_BIND | MS_REC, "") < 0) {
        fprintf(stderr, "warning: failed to mount /dev: %s\n", strerror(errno));
    }
    if (mount("proc", proc_dir, "proc", 0, "") < 0) {
        fprintf(stderr, "warning: failed to mount /proc: %s\n", strerror(errno));
    }
    /* Bind mount /sys since mounting sysfs in user namespace may not work */
    if (mount("/sys", sys_dir, "", MS_BIND | MS_REC | MS_RDONLY, "") < 0) {
        fprintf(stderr, "warning: failed to mount /sys: %s\n", strerror(errno));
    }
    if (mount("tmpfs", tmp_dir, "tmpfs", 0, "") < 0) {
        fprintf(stderr, "warning: failed to mount /tmp: %s\n", strerror(errno));
    }
}
