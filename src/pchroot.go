package main

import (
	"fmt"
	"os"
	"os/exec"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"
)

func fatalf(format string, a ...interface{}) {
	fmt.Fprintf(os.Stderr, format+"\n", a...)
	os.Exit(1)
}

func usage() {
	fmt.Fprintf(os.Stderr, "usage: %s <newRoot> <cmdPath> <cmdArgs...>\n", os.Args[0])
	os.Exit(2)
}

func main() {
	newRoot := os.Args[1]
	cmdPath := os.Args[2]
	cmdArgs := os.Args[3:]

	if err := runHelper(newRoot, cmdPath, cmdArgs); err != nil {
		fatalf("error: %v", err)
	}
}

// runHelper performs mounts, chroot, exec target, cleanup.
func runHelper(newRoot, cmdPath string, cmdArgs []string) error {
	// Resolve newRoot absolute path
	newRootAbs, err := filepath.Abs(newRoot)
	if err != nil {
		return fmt.Errorf("invalid newRoot: %w", err)
	}

	// Unshare mount namespace to make mounts private to this helper if not already in a private namespace.
	// If the caller already created CLONE_NEWNS, this is harmless: we simply ensure private propagation.
	if err := syscall.Unshare(syscall.CLONE_NEWNS); err != nil {
		// On some systems Unshare may fail if not allowed; continue but warn.
		fmt.Fprintf(os.Stderr, "warning: unshare(CLONE_NEWNS) failed: %v\n", err)
	}
	// Make mounts private so our mounts don't propagate to other namespaces.
	if err := syscall.Mount("", "/", "", uintptr(syscall.MS_REC|syscall.MS_PRIVATE), ""); err != nil {
		// Non-fatal: warn and continue
		fmt.Fprintf(os.Stderr, "warning: mount --make-rprivate failed: %v\n", err)
	}

	// Ensure mount points exist
	procDir := filepath.Join(newRootAbs, "proc")
	sysDir := filepath.Join(newRootAbs, "sys")
	devDir := filepath.Join(newRootAbs, "dev")
	devPtsDir := filepath.Join(devDir, "pts")

	for _, d := range []string{procDir, sysDir, devDir, devPtsDir} {
		if err := os.MkdirAll(d, 0755); err != nil {
			return fmt.Errorf("mkdir %s: %w", d, err)
		}
	}

	// collect mounted targets for cleanup in reverse order
	var mounted []string
	addMount := func(target string) { mounted = append(mounted, target) }

	// Helper to unmount in reverse order using MNT_DETACH (lazy) first, then force attempt
	unmountAll := func() {
		for i := len(mounted) - 1; i >= 0; i-- {
			t := mounted[i]
			// Try lazy unmount first so we won't block
			if err := syscall.Unmount(t, syscall.MNT_DETACH); err != nil {
				// fallback to normal unmount
				if err2 := syscall.Unmount(t, 0); err2 != nil {
					fmt.Fprintf(os.Stderr, "warning: failed to unmount %s: %v (fallback err: %v)\n", t, err, err2)
				}
			}
		}
	}

	// Attempt bind-mount /dev into newRoot/dev (recursive bind)
	if err := syscall.Mount("/dev", devDir, "", syscall.MS_BIND|syscall.MS_REC, ""); err != nil {
		fmt.Fprintf(os.Stderr, "warning: bind mount /dev -> %s failed: %v\n", devDir, err)
	} else {
		addMount(devDir)
	}

	// Mount devpts on newRoot/dev/pts
	if err := syscall.Mount("devpts", devPtsDir, "devpts", 0, "mode=0620,ptmxmode=0666"); err != nil {
		fmt.Fprintf(os.Stderr, "warning: mount devpts (%s) failed: %v\n", devPtsDir, err)
	} else {
		addMount(devPtsDir)
	}

	// Mount proc
	if err := syscall.Mount("proc", procDir, "proc", 0, ""); err != nil {
		fmt.Fprintf(os.Stderr, "warning: mount proc (%s) failed: %v\n", procDir, err)
	} else {
		addMount(procDir)
	}

	// Mount sysfs
	if err := syscall.Mount("sysfs", sysDir, "sysfs", 0, ""); err != nil {
		fmt.Fprintf(os.Stderr, "warning: mount sysfs (%s) failed: %v\n", sysDir, err)
	} else {
		addMount(sysDir)
	}

	// Prepare signal handling & child management
	sigch := make(chan os.Signal, 1)
	// catch signals that allow us to run cleanup. SIGKILL cannot be caught.
	signal.Notify(sigch, syscall.SIGINT, syscall.SIGTERM, syscall.SIGHUP, syscall.SIGQUIT)

	// We will start the child and wait for it; if we receive signals, kill child's process group and cleanup.
	// Use a channel to get child exit info.
	childExit := make(chan error, 1)

	// Start the child process
	childCmd := exec.Command(cmdPath, cmdArgs...)
	// inherit environment; caller can set env via parent
	childCmd.Env = os.Environ()
	childCmd.Stdin = os.Stdin
	childCmd.Stdout = os.Stdout
	childCmd.Stderr = os.Stderr

	// Ensure the child gets SIGKILL if helper dies unexpectedly,
	// and run child in its own process group so we can kill whole session.
	childCmd.SysProcAttr = &syscall.SysProcAttr{
		Setpgid:   true,            // child becomes leader of new process group
		Pdeathsig: syscall.SIGKILL, // kernel will send SIGKILL to child if parent dies
	}

	// Do chroot and chdir before starting the child
	if err := syscall.Chroot(newRootAbs); err != nil {
		// try to cleanup mounts before returning error
		unmountAll()
		return fmt.Errorf("chroot(%s) failed: %w", newRootAbs, err)
	}
	if err := syscall.Chdir("/"); err != nil {
		unmountAll()
		return fmt.Errorf("chdir after chroot failed: %w", err)
	}

	// Start child
	if err := childCmd.Start(); err != nil {
		unmountAll()
		return fmt.Errorf("failed to start child: %w", err)
	}

	// child process group id (negative pid can be used to signal group)
	childPid := childCmd.Process.Pid
	childPgid, err := syscall.Getpgid(childPid)
	if err != nil {
		// fallback: pgid = pid
		childPgid = childPid
	}

	go func() {
		// Wait for child to finish and send result
		err := childCmd.Wait()
		childExit <- err
	}()

	cleanupAndKillChildGroup := func() {
		// attempt to kill the child's process group
		// send SIGKILL to the whole group: negative pgid
		// ignore errors (processes might already be gone)
		if childPgid > 0 {
			// use Kill with negative pgid to target group
			syscall.Kill(-childPgid, syscall.SIGKILL)
			// also try direct pid kill
			syscall.Kill(childPid, syscall.SIGKILL)
		}
		// allow some time for processes to terminate, then unmount
		time.Sleep(50 * time.Millisecond)
		unmountAll()
	}

	// Main wait loop: either child finishes, or we get a signal
	select {
	case sig := <-sigch:
		// Received termination signal: ensure child group is killed and cleanup runs
		fmt.Fprintf(os.Stderr, "helper: received signal %v, terminating child group and cleaning up\n", sig)
		cleanupAndKillChildGroup()
		// after cleanup return non-zero to indicate signal
		return fmt.Errorf("terminated by signal %v", sig)
	case err := <-childExit:
		// child ended naturally; capture exit code, cleanup, and return with same code
		// Unmount before returning
		unmountAll()
		if err == nil {
			// success
			return nil
		}
		// If child exited with an exit status, extract it and exit with same code
		if ws, ok := err.(*exec.ExitError); ok {
			if status, ok := ws.Sys().(syscall.WaitStatus); ok {
				// use os.Exit in main to set precise code; here return an error encoding the code
				return exitErrorWithCode(status.ExitStatus())
			}
		}
		return fmt.Errorf("child failed: %w", err)
	}
}

// exitErrorWithCode returns an error that encodes an exit code; main treats any non-nil as fatal and exits 1,
// but callers can parse if necessary. We return a recognizable error string.
func exitErrorWithCode(code int) error {
	return fmt.Errorf("exitcode:%d", code)
}
