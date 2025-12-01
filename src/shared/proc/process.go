package proc

import (
	"errors"
	"os"
	"os/exec"
	"syscall"
	"time"
)

type RunningPidsCollection []int

var RunningPids = RunningPidsCollection{}

func (r *RunningPidsCollection) AddProcessId(pid int) error {
	// Get the process
	process, err := os.FindProcess(pid)
	if err != nil {
		return err
	}

	// Send signal 0 to check if the process is running
	err2 := process.Signal(syscall.Signal(0))
	if err2 != nil {
		return err2
	}

	// If no error, the process is running; add to collection
	r.AddProcess(process)
	return nil
}

func (r *RunningPidsCollection) AddProcess(process *os.Process) error {
	if process == nil {
		return errors.New("process is nil")
	}
	pid := process.Pid
	if pid <= 0 {
		return errors.New("invalid process ID")
	}

	// Add the process ID to the collection
	*r = append(*r, pid)
	return nil
}

func (r *RunningPidsCollection) KillProcess(pid int, timeoutSeconds int) error {
	process, err := os.FindProcess(pid)
	if err != nil {
		return err
	}

	// Send SIGHUP to allow graceful shutdown
	err = process.Signal(syscall.SIGHUP)
	if err != nil {
		return err
	}

	// Wait for the process to exit or if it exceeds timeout, send SIGKILL
	done := make(chan error, 1)
	go func() {
		_, err := process.Wait()
		done <- err
	}()

	select {
	case <-done:
		// Process exited gracefully
		return nil
	case <-time.After(time.Duration(timeoutSeconds) * time.Second):
		// Timeout exceeded, force kill the process
		err = process.Kill()
		if err != nil {
			return err
		}
	}

	// TODO: Remove pid from RunningPidsCollection in optimized way

	return nil
}

func (r *RunningPidsCollection) KillAllProcesses(timeoutSeconds int) {
	for _, pid := range *r {
		_ = r.KillProcess(pid, timeoutSeconds)
	}

	// Clear the collection
	*r = RunningPidsCollection{}
}

func (r *RunningPidsCollection) ListProcesses() []*os.Process {
	var processes []*os.Process
	for _, pid := range *r {
		process, err := os.FindProcess(pid)
		if err == nil {
			processes = append(processes, process)
		}
	}
	return processes
}

// ResolveExecutablePath checks if an executable exists in the system's PATH
// and returns a boolean indicating its presence along with its full path.
func ResolveExecutablePath(executable string) (bool, string) {
	path, err := exec.LookPath(executable)
	return err == nil, path
}

func GetCmd(executable string, args []string, envVars map[string]string, stdin *os.File, stdout *os.File, stderr *os.File) *exec.Cmd {
	cmd := exec.Command(executable, args...)

	// Set up environment variables for the new process
	// Copy our environment map
	env := EnvironmentVariables
	// Override with provided envVars
	for k, v := range envVars {
		env.Set(k, v)
	}

	cmd.Env = env.ToSlice()

	// Set the standard input, output, and error to those of the current process if not provided
	if stdin == nil {
		cmd.Stdin = os.Stdin
	} else {
		cmd.Stdin = stdin
	}

	if stdout == nil {
		cmd.Stdout = os.Stdout
	} else {
		cmd.Stdout = stdout
	}

	if stderr == nil {
		cmd.Stderr = os.Stderr
	} else {
		cmd.Stderr = stderr
	}

	return cmd
}

// StartProcess starts the given command as a new process and invokes the
// exitCallback function when the process exits, passing any error encountered.
// It also tracks the process ID in the RunningPids collection.
// Note: The exitCallback is called in the same goroutine that waits for the process to exit.
// Invoke StartProcess in a separate goroutine if non-blocking behavior is desired.
func StartProcess(cmd *exec.Cmd, exitCallback func(*exec.Cmd, error)) {
	err := cmd.Start()
	if err != nil {
		exitCallback(cmd, err)
		return
	}

	RunningPids.AddProcessId(cmd.Process.Pid)
	err = cmd.Wait()

	// TODO: Remove pid from collection

	exitCallback(cmd, err)
}
