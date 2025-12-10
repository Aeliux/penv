/* overlayfs.c - OverlayFS setup and management */
#include "rootbox.h"
#include <time.h>

/* Cleanup helper for setup_overlayfs error paths */
static void cleanup_ofs_setup(char *merged, char *workdir, char *upperdir, int cleanup_upper) {
    if (cleanup_upper && upperdir) {
        rmdir(upperdir);
        free(upperdir);
    }
    if (workdir) {
        rmdir(workdir);
        free(workdir);
    }
    if (merged) {
        rmdir(merged);
        free(merged);
    }
}

/* Setup overlayfs mount, returning merged path */
char *setup_overlayfs(const char *image_path, const char *persist_path) {
    char *merged = malloc(PATH_MAX);
    char *workdir = malloc(PATH_MAX);
    char *upperdir = NULL;
    char opts[PATH_MAX * 3];
    int cleanup_upper = 0;
    
    if (!merged || !workdir) {
        fprintf(stderr, "rootbox-ofs: malloc failed: %s\r\n", strerror(errno));
        free(merged);
        free(workdir);
        return NULL;
    }
    
    snprintf(merged, PATH_MAX, "/tmp/rootbox-ofs-%d-%ld-merged", getpid(), time(NULL));
    snprintf(workdir, PATH_MAX, "/tmp/rootbox-ofs-%d-%ld-work", getpid(), time(NULL));
    
    /* Create merged and work directories */
    if (mkdir(merged, 0755) < 0) {
        fprintf(stderr, "rootbox-ofs: failed to create merged dir: %s\r\n", strerror(errno));
        free(merged);
        free(workdir);
        return NULL;
    }
    
    if (mkdir(workdir, 0755) < 0) {
        fprintf(stderr, "rootbox-ofs: failed to create work dir: %s\r\n", strerror(errno));
        cleanup_ofs_setup(merged, NULL, NULL, 0);
        free(workdir);
        return NULL;
    }
    
    /* Determine upperdir */
    if (persist_path) {
        /* Use persistence directory as upperdir */
        upperdir = (char *)persist_path;
        
        /* Create persistence directory if it doesn't exist */
        if (mkdir(persist_path, 0755) < 0 && errno != EEXIST) {
            fprintf(stderr, "rootbox-ofs: failed to create persistence dir: %s\r\n", strerror(errno));
            cleanup_ofs_setup(merged, workdir, NULL, 0);
            return NULL;
        }
        
        fprintf(stderr, "rootbox-ofs: mounting overlayfs (persistent) at %s\r\n", merged);
    } else {
        /* Create temporary upperdir */
        upperdir = malloc(PATH_MAX);
        if (!upperdir) {
            fprintf(stderr, "rootbox-ofs: malloc failed: %s\r\n", strerror(errno));
            cleanup_ofs_setup(merged, workdir, NULL, 0);
            return NULL;
        }
        
        snprintf(upperdir, PATH_MAX, "/tmp/rootbox-ofs-%d-%ld-upper", getpid(), time(NULL));
        if (mkdir(upperdir, 0755) < 0) {
            fprintf(stderr, "rootbox-ofs: failed to create upper dir: %s\r\n", strerror(errno));
            cleanup_ofs_setup(merged, workdir, upperdir, 1);
            return NULL;
        }
        
        cleanup_upper = 1;
        fprintf(stderr, "rootbox-ofs: mounting overlayfs (ephemeral) at %s\r\n", merged);
    }
    
    /* Mount overlayfs */
    snprintf(opts, sizeof(opts), "lowerdir=%s,upperdir=%s,workdir=%s", 
             image_path, upperdir, workdir);
    
    if (mount("overlay", merged, "overlay", 0, opts) < 0) {
        fprintf(stderr, "rootbox-ofs: mount overlayfs failed: %s\r\n", strerror(errno));
        cleanup_ofs_setup(merged, workdir, upperdir, cleanup_upper);
        return NULL;
    }
    
    /* Store workdir path for cleanup */
    char metadata[PATH_MAX];
    snprintf(metadata, sizeof(metadata), "%s/.rootbox-meta", merged);
    FILE *f = fopen(metadata, "w");
    if (f) {
        fprintf(f, "WORKDIR=%s\n", workdir);
        if (cleanup_upper) {
            fprintf(f, "UPPERDIR=%s\n", upperdir);
        }
        fclose(f);
    } else {
        fprintf(stderr, "rootbox-ofs: warning: failed to create metadata: %s\r\n", strerror(errno));
    }
    
    if (cleanup_upper) {
        free(upperdir);
    }
    free(workdir);
    
    return merged;
}

/* Cleanup overlayfs */
void cleanup_overlayfs(const char *merged_path) {
    char metadata[PATH_MAX];
    char workdir[PATH_MAX] = {0};
    char upperdir[PATH_MAX] = {0};
    char line[PATH_MAX];
    
    if (!merged_path) return;
    
    /* Read metadata */
    snprintf(metadata, sizeof(metadata), "%s/.rootbox-meta", merged_path);
    FILE *f = fopen(metadata, "r");
    if (f) {
        while (fgets(line, sizeof(line), f)) {
            if (strncmp(line, "WORKDIR=", 8) == 0) {
                sscanf(line, "WORKDIR=%s", workdir);
            } else if (strncmp(line, "UPPERDIR=", 9) == 0) {
                sscanf(line, "UPPERDIR=%s", upperdir);
            }
        }
        fclose(f);
    } else {
        fprintf(stderr, "rootbox-ofs: warning: failed to read metadata: %s\r\n", strerror(errno));
    }
    
    /* Unmount overlayfs */
    if (umount2(merged_path, MNT_DETACH) < 0) {
        fprintf(stderr, "rootbox-ofs: umount overlayfs failed: %s\r\n", strerror(errno));
    }
    
    /* Remove temporary directories */
    if (upperdir[0]) {
        if (remove_dir_recursive(upperdir) < 0) {
            fprintf(stderr, "rootbox-ofs: warning: failed to remove %s: %s\r\n", upperdir, strerror(errno));
        }
    }
    
    if (workdir[0]) {
        if (remove_dir_recursive(workdir) < 0) {
            fprintf(stderr, "rootbox-ofs: warning: failed to remove %s: %s\r\n", workdir, strerror(errno));
        }
    }
    
    if (rmdir(merged_path) < 0) {
        fprintf(stderr, "rootbox-ofs: warning: failed to remove %s: %s\r\n", merged_path, strerror(errno));
    }
}
