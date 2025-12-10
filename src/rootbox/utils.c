/* utils.c - Utility functions */
#include "rootbox.h"

void fatal(const char *msg) {
    fprintf(stderr, "rootbox: %s: %s\n", msg, strerror(errno));
    exit(1);
}

void mkdirp(const char *path) {
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

void write_file(const char *path, const char *content) {
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

int remove_dir_recursive(const char *path) {
    DIR *d = opendir(path);
    size_t path_len = strlen(path);
    int r = -1;

    if (d) {
        struct dirent *p;
        r = 0;
        while (!r && (p = readdir(d))) {
            int r2 = -1;
            char *buf;
            size_t len;

            /* Skip "." and ".." */
            if (!strcmp(p->d_name, ".") || !strcmp(p->d_name, ".."))
                continue;

            len = path_len + strlen(p->d_name) + 2;
            buf = malloc(len);
            if (buf) {
                struct stat statbuf;
                snprintf(buf, len, "%s/%s", path, p->d_name);
                if (!stat(buf, &statbuf)) {
                    if (S_ISDIR(statbuf.st_mode))
                        r2 = remove_dir_recursive(buf);
                    else
                        r2 = unlink(buf);
                }
                free(buf);
            }
            r = r2;
        }
        closedir(d);
    }
    if (!r)
        r = rmdir(path);
    return r;
}
