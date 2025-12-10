/* namespace.c - User namespace setup */
#include "rootbox.h"

void setup_uid_map(pid_t pid, uid_t outer_uid) {
    char path[256], map[256];
    snprintf(path, sizeof(path), "/proc/%d/uid_map", pid);
    /* Map current user to root inside namespace (standard approach) */
    snprintf(map, sizeof(map), "0 %d 1\n", outer_uid);
    write_file(path, map);
}

void setup_gid_map(pid_t pid, gid_t outer_gid) {
    char path[256], map[256];
    snprintf(path, sizeof(path), "/proc/%d/setgroups", pid);
    write_file(path, "deny\n");
    snprintf(path, sizeof(path), "/proc/%d/gid_map", pid);
    /* Map current group to root inside namespace (standard approach) */
    snprintf(map, sizeof(map), "0 %d 1\n", outer_gid);
    write_file(path, map);
}

void setup_user_namespace(uid_t outer_uid, gid_t outer_gid) {
    if (unshare(CLONE_NEWUSER) < 0) fatal("unshare(CLONE_NEWUSER) failed");
    setup_uid_map(getpid(), outer_uid);
    setup_gid_map(getpid(), outer_gid);
}
