/* main.c - Main entry point for rootbox */
#include "rootbox.h"

extern char **environ;

static void usage(const char *prog_name) {
    int is_ofs = (strcmp(prog_name, "rootbox-ofs") == 0);
    
    fprintf(stderr, "Usage:\n");
    if (is_ofs) {
        fprintf(stderr, "  %s <rootDir> -- <cmd> [args...]              - OverlayFS ephemeral mode\n", prog_name);
        fprintf(stderr, "  %s <rootDir> -p <persist> -- <cmd> [args...] - OverlayFS persistent mode\n", prog_name);
    } else {
        fprintf(stderr, "  %s <rootDir> -- <cmd> [args...]              - Direct chroot mode\n", prog_name);
    }
    exit(2);
}

static rootbox_args_t parse_args(int argc, char **argv) {
    rootbox_args_t args = {0};
    
    /* Check if we're in OFS mode based on argv[0] */
    const char *prog_name = strrchr(argv[0], '/');
    prog_name = prog_name ? prog_name + 1 : argv[0];
    args.is_ofs_mode = (strcmp(prog_name, "rootbox-ofs") == 0);
    
    /* Minimum: prog rootDir -- cmd */
    if (argc < 4) usage(prog_name);
    
    args.image_path = argv[1];
    
    /* Parse optional -p flag (only for OFS mode) */
    int arg_idx = 2;
    if (args.is_ofs_mode && arg_idx < argc - 2) {
        if (strcmp(argv[arg_idx], "-p") == 0) {
            if (arg_idx + 1 >= argc) {
                fprintf(stderr, "rootbox: -p requires an argument\n");
                usage(prog_name);
            }
            args.persist_path = argv[arg_idx + 1];
            arg_idx += 2;
        }
    }
    
    /* Look for -- separator */
    if (arg_idx >= argc || strcmp(argv[arg_idx], "--") != 0) {
        fprintf(stderr, "rootbox: missing '--' separator before command\n");
        usage(prog_name);
    }
    arg_idx++;  /* Skip -- */
    
    if (arg_idx >= argc) {
        fprintf(stderr, "rootbox: no command specified after '--'\n");
        usage(prog_name);
    }
    
    args.cmd_path = argv[arg_idx];
    args.cmd_args = argv + arg_idx;
    
    return args;
}

static void setup_namespaces(rootbox_args_t *args, uid_t original_uid, gid_t original_gid) {
    if (prctl(PR_SET_PDEATHSIG, SIGKILL) < 0) {
        fprintf(stderr, "warning: PR_SET_PDEATHSIG failed: %s\r\n", strerror(errno));
    }
    
    /* Try to create user namespace if not root */
    if (geteuid() != 0) {
        setup_user_namespace(original_uid, original_gid);
    }
    
    /* Unshare mount, PID and UTS namespaces */
    if (unshare(CLONE_NEWNS | CLONE_NEWPID | CLONE_NEWUTS) < 0) {
        fprintf(stderr, "warning: unshare failed: %s\r\n", strerror(errno));
    }
    
    /* Set hostname */
    const char *hostname = args->is_ofs_mode ? "rootbox-ofs" : "rootbox";
    size_t hostname_len = strlen(hostname);
    if (sethostname(hostname, hostname_len) < 0) {
        fprintf(stderr, "warning: sethostname failed: %s\r\n", strerror(errno));
    }
    if (setdomainname(hostname, hostname_len) < 0) {
        fprintf(stderr, "warning: setdomainname failed: %s\r\n", strerror(errno));
    }
}

static void parent_io_handler(int master_fd, int slave_fd, pid_t pid, 
                              struct termios *saved_tio, int saved_tty, 
                              char *merged_path) {
    close(slave_fd);
    
    if (isatty(STDIN_FILENO)) {
        struct termios raw = *saved_tio;
        cfmakeraw(&raw);
        tcsetattr(STDIN_FILENO, TCSANOW, &raw);
    }
    
    io_loop(master_fd, pid);
    
    int status;
    waitpid(pid, &status, 0);
    
    close(master_fd);
    if (saved_tty) {
        restore_tty(STDIN_FILENO, saved_tio);
    }
    
    /* Cleanup overlayfs if needed */
    if (merged_path) {
        cleanup_overlayfs(merged_path);
        free(merged_path);
    }
    
    exit(WIFEXITED(status) ? WEXITSTATUS(status) : 1);
}

static void child_setup_and_exec(rootbox_args_t *args, int master_fd, int slave_fd) {
    close(master_fd);
    make_mount_private();
    
    char *root_path;
    
    if (args->is_ofs_mode) {
        /* Setup overlayfs */
        root_path = setup_overlayfs(args->image_path, args->persist_path);
        if (!root_path) {
            fatal("failed to setup overlayfs");
        }
    } else {
        /* Use directory directly */
        root_path = args->image_path;
    }
    
    setup_basic_mounts(root_path);
    
    if (chroot(root_path) < 0) fatal("chroot failed");
    if (chdir("/") < 0) fatal("chdir failed");
    
    setup_pty_slave(slave_fd);
    
    prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
    
    execve(args->cmd_path, args->cmd_args, environ);
    fatal("execve failed");
}

int main(int argc, char **argv) {
    rootbox_args_t args = parse_args(argc, argv);
    uid_t original_uid = getuid();
    gid_t original_gid = getgid();
    int master_fd = -1, slave_fd = -1;
    struct termios saved_tio;
    int saved_tty = 0;
    
    /* Save terminal settings */
    if (isatty(STDIN_FILENO) && tcgetattr(STDIN_FILENO, &saved_tio) == 0) {
        saved_tty = 1;
    }
    
    /* Setup PTY */
    if (setup_pty(&master_fd, &slave_fd) < 0) {
        fatal("failed to create PTY");
    }
    
    /* Setup namespaces */
    setup_namespaces(&args, original_uid, original_gid);
    
    /* Fork - child becomes PID 1 */
    pid_t pid = fork();
    if (pid < 0) fatal("fork failed");
    
    if (pid > 0) {
        /* Parent process - handle I/O and cleanup */
        parent_io_handler(master_fd, slave_fd, pid, &saved_tio, saved_tty, NULL);
    }
    
    /* Child (PID 1) continues */
    child_setup_and_exec(&args, master_fd, slave_fd);
    
    return 0;
}
