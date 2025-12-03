package hook

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"time"

	"penv/shared/logger"
	"penv/shared/proc"
)

// Executor handles the execution of hooks
type Executor struct {
	graph          *DependencyGraph
	executions     map[string]*HookExecution
	executionsMux  sync.RWMutex
	defaultWorkDir string
	mode           ExecutionMode
	trigger        Trigger
}

// NewExecutor creates a new hook executor
func NewExecutor(graph *DependencyGraph, defaultWorkDir string, mode ExecutionMode, trigger Trigger) *Executor {
	if defaultWorkDir == "" {
		defaultWorkDir = "/"
	}

	return &Executor{
		graph:          graph,
		executions:     make(map[string]*HookExecution),
		defaultWorkDir: defaultWorkDir,
		mode:           mode,
		trigger:        trigger,
	}
}

// ExecuteBatches executes hooks in batches (parallel within batch, sequential between batches)
func (e *Executor) ExecuteBatches(batches [][]string) error {
	var firstError error

	for batchNum, batch := range batches {
		logger.S.Infof("Executing batch %d with %d hook(s)", batchNum+1, len(batch))

		if err := e.executeBatch(batch); err != nil {
			if firstError == nil {
				firstError = fmt.Errorf("batch %d failed: %w", batchNum+1, err)
			}
			logger.S.Warnf("Batch %d failed, continuing to process dependencies", batchNum+1)
			// Continue to next batch to properly skip dependent hooks
		}
	}

	return firstError
}

// executeBatch executes all hooks in a batch in parallel
func (e *Executor) executeBatch(batch []string) error {
	var wg sync.WaitGroup
	errChan := make(chan error, len(batch))

	for _, hookName := range batch {
		hook, exists := e.graph.GetHook(hookName)
		if !exists {
			return fmt.Errorf("hook not found: %s", hookName)
		}

		wg.Add(1)
		go func(h *Hook) {
			defer wg.Done()

			if err := e.executeHook(h); err != nil {
				errChan <- fmt.Errorf("hook '%s' failed: %w", h.Name, err)
			}
		}(hook)
	}

	wg.Wait()
	close(errChan)

	// Check for errors
	var errors []error
	for err := range errChan {
		errors = append(errors, err)
	}

	if len(errors) > 0 {
		return fmt.Errorf("batch execution failed with %d error(s): %v", len(errors), errors)
	}

	return nil
}

// executeHook executes a single hook
func (e *Executor) executeHook(hook *Hook) error {
	// Check dependencies
	depStatuses := make(map[string]ExecutionStatus)
	for _, depName := range hook.Requires {
		depExec, exists := e.GetExecution(depName)
		if !exists {
			// Dependency not executed yet (shouldn't happen with proper topological sort)
			execution := &HookExecution{
				Hook:         hook,
				Status:       StatusSkipped,
				StartTime:    time.Now(),
				EndTime:      time.Now(),
				SkipReason:   fmt.Sprintf("dependency '%s' not executed", depName),
				Dependencies: depStatuses,
			}
			e.setExecution(hook.Name, execution)
			logger.S.Warnf("Skipping hook '%s': dependency '%s' not executed", hook.Name, depName)
			return fmt.Errorf("dependency '%s' not executed", depName)
		}

		depStatuses[depName] = depExec.Status

		// Check if dependency completed successfully
		if depExec.Status != StatusCompleted {
			execution := &HookExecution{
				Hook:         hook,
				Status:       StatusSkipped,
				StartTime:    time.Now(),
				EndTime:      time.Now(),
				SkipReason:   fmt.Sprintf("dependency '%s' failed with status: %s", depName, depExec.Status),
				Dependencies: depStatuses,
			}
			e.setExecution(hook.Name, execution)
			logger.S.Warnf("Skipping hook '%s': dependency '%s' %s", hook.Name, depName, depExec.Status)
			return fmt.Errorf("dependency '%s' %s", depName, depExec.Status)
		}
	}

	if len(hook.PersistentEnv) > 0 {
		logger.S.Debugf("Applying %d persistent environment variables from hook '%s'", len(hook.PersistentEnv), hook.Name)

		for _, envVar := range hook.PersistentEnv {
			expandedValue := os.Expand(envVar.Value, func(varName string) string {
				val, _ := proc.EnvironmentVariables.Get(varName)
				return val
			})

			proc.EnvironmentVariables.Set(envVar.Key, expandedValue)
			logger.S.Infof("Set persistent env var: %s=%s", envVar.Key, expandedValue)
		}
	}

	// If hook has no run section, it's an env-only hook
	if hook.RunType == "" {
		logger.S.Infof("Hook '%s' is env-only (no run section), environment updated", hook.Name)
		execution := &HookExecution{
			Hook:      hook,
			Status:    StatusCompleted,
			StartTime: time.Now(),
			EndTime:   time.Now(),
		}
		e.setExecution(hook.Name, execution)
		return nil
	}

	execution := &HookExecution{
		Hook:         hook,
		Status:       StatusRunning,
		StartTime:    time.Now(),
		Dependencies: depStatuses,
	}

	e.setExecution(hook.Name, execution)
	logger.S.Infof("Executing hook: %s", hook.Name)

	var err error
	var exCode int
	switch hook.RunType {
	case RunTypeCommand:
		exCode, err = e.executeCommand(hook, execution)
	case RunTypeShell:
		exCode, err = e.executeShell(hook, execution)
	case RunTypeService:
		exCode, err = e.executeService(hook, execution)
	default:
		exCode, err = -1, fmt.Errorf("unknown run type: %s", hook.RunType)
	}

	execution.EndTime = time.Now()
	if err != nil {
		execution.Status = StatusFailed
		execution.Error = err
		execution.ExitCode = exCode
		logger.S.Errorf("Hook '%s' failed: %v", hook.Name, err)
		return err
	}

	execution.Status = StatusCompleted
	logger.S.Infof("Hook '%s' completed successfully", hook.Name)
	e.setExecution(hook.Name, execution)

	return nil
}

// createCommand creates a configured exec.Cmd for a hook
func (e *Executor) createCommand(hook *Hook, command string, args []string) *exec.Cmd {
	env := make(map[string]string)

	// Copy hook's run-only environment variables and expand them
	for _, envVar := range hook.RunEnv {
		env[envVar.Key] = os.Expand(envVar.Value, func(varName string) string {
			// First check in our local env map
			if val, exists := env[varName]; exists {
				return val
			}
			// Then check in proc.EnvironmentVariables
			val, _ := proc.EnvironmentVariables.Get(varName)
			return val
		})
	}

	// Add PINIT_HOOK variables
	env["PINIT_HOOK"] = hook.Name
	env["PINIT_HOOK_PATH"] = hook.FilePath
	env["PINIT_HOOK_MODE"] = string(e.mode)
	env["PINIT_HOOK_TRIGGER"] = string(e.trigger)

	cmd := proc.GetCmd(command, args, env, nil, nil, nil)

	// Set working directory
	workDir := hook.WorkDir
	if workDir == "" {
		workDir = e.defaultWorkDir
	}
	cmd.Dir = workDir

	return cmd
}

// runCommandWithWait executes a command and waits for completion, checking success codes
func (e *Executor) runCommandWithWait(cmd *exec.Cmd, hook *Hook, cmdDescription string) (int, error) {
	logger.S.Debugf("Running %s for hook '%s' (workdir: %s)", cmdDescription, hook.Name, cmd.Dir)

	if err := cmd.Run(); err != nil {
		if cmd.ProcessState != nil {
			exitCode := cmd.ProcessState.ExitCode()
			if !e.isSuccessCode(hook, exitCode) {
				return exitCode, fmt.Errorf("%s exited with non-success code: %d", cmdDescription, exitCode)
			}
		} else {
			return -1, fmt.Errorf("%s failed: %w", cmdDescription, err)
		}
	}

	return 0, nil
}

// executeCommand executes a command hook
func (e *Executor) executeCommand(hook *Hook, execution *HookExecution) (int, error) {
	// Parse command and arguments
	parts := strings.Fields(hook.Command)
	if len(parts) == 0 {
		return -1, fmt.Errorf("empty command")
	}

	cmd := e.createCommand(hook, parts[0], parts[1:])
	return e.runCommandWithWait(cmd, hook, "command")
}

// executeShell executes a shell script hook
func (e *Executor) executeShell(hook *Hook, execution *HookExecution) (int, error) {
	// Create a temporary script file
	tmpDir := os.TempDir()
	scriptPath := filepath.Join(tmpDir, fmt.Sprintf("hook-%s-%d.sh", hook.Name, time.Now().UnixNano()))

	if err := os.WriteFile(scriptPath, []byte(hook.Shell), 0755); err != nil {
		return -1, fmt.Errorf("failed to create script file: %w", err)
	}
	defer os.Remove(scriptPath)

	cmd := e.createCommand(hook, scriptPath, []string{})
	return e.runCommandWithWait(cmd, hook, "shell script")
}

// executeService starts a service hook
func (e *Executor) executeService(hook *Hook, execution *HookExecution) (int, error) {
	// Check if service is already running globally
	if existing, exists := GetGlobalService(hook.Name); exists {
		pid := existing.GetPID()
		logger.S.Infof("Service '%s' already running with PID %d, skipping start", hook.Name, pid)
		execution.PID = pid
		return 0, nil
	}

	// Parse service command and arguments
	parts := strings.Fields(hook.Service)
	if len(parts) == 0 {
		return -1, fmt.Errorf("empty service command")
	}

	cmd := e.createCommand(hook, parts[0], parts[1:])

	logger.S.Infof("Starting service: %s (workdir: %s)", hook.Service, cmd.Dir)

	// Start the service process
	serviceState := &ServiceState{
		Hook:      hook,
		StartTime: time.Now(),
	}
	serviceState.SetActive(true)

	// Channel to communicate startup status
	startupDone := make(chan error, 1)

	// Start process in background with restart handling
	go e.manageService(cmd, serviceState, startupDone)

	// Wait for startup to complete or fail
	select {
	case err := <-startupDone:
		if err != nil {
			return -1, err
		}
		// Startup successful, register the service
		RegisterGlobalService(hook.Name, serviceState)
		execution.PID = serviceState.GetPID()
		return 0, nil
	case <-time.After(5 * time.Second):
		// Timeout waiting for service to start
		serviceState.SetActive(false)
		return -1, fmt.Errorf("timeout waiting for service to start")
	}
}

// manageService handles service lifecycle including restarts
func (e *Executor) manageService(cmd *exec.Cmd, state *ServiceState, startupDone chan error) {
	firstStart := true
	for {
		err := cmd.Start()
		if err != nil {
			logger.S.Errorf("Service '%s' failed to start: %v", state.Hook.Name, err)
			state.SetActive(false)
			if firstStart {
				startupDone <- fmt.Errorf("service failed to start: %w", err)
			}
			return
		}

		state.SetPID(cmd.Process.Pid)
		// Only add to RunningPids on first start (RegisterGlobalService already added it)
		if !firstStart {
			proc.RunningPids.AddProcess(cmd.Process)
		}

		// Signal successful startup on first start
		if firstStart {
			firstStart = false
			startupDone <- nil
		}

		logger.S.Infof("Service '%s' started with PID %d", state.Hook.Name, state.GetPID())

		// Wait for process to exit
		cmd.Wait()

		exitCode := 0
		if cmd.ProcessState != nil {
			exitCode = cmd.ProcessState.ExitCode()
		}

		logger.S.Warnf("Service '%s' (PID %d) exited with code %d", state.Hook.Name, state.GetPID(), exitCode)

		// Check if exit code is considered success
		if e.isSuccessCode(state.Hook, exitCode) {
			logger.S.Infof("Service '%s' exited successfully", state.Hook.Name)
			state.SetActive(false)
			UnregisterGlobalService(state.Hook.Name)
			return
		}

		// Check if restart is enabled
		if !state.Hook.Restart {
			logger.S.Errorf("Service '%s' failed and restart is disabled", state.Hook.Name)
			state.SetActive(false)
			UnregisterGlobalService(state.Hook.Name)
			return
		}

		// Check restart limit
		restarts := state.GetRestarts()
		if restarts >= 10 {
			logger.S.Errorf("Service '%s' reached maximum restart attempts (%d), not restarting", state.Hook.Name, restarts)
			state.SetActive(false)
			UnregisterGlobalService(state.Hook.Name)
			return
		}

		// Restart the service
		restarts = state.IncrementRestarts()
		logger.S.Infof("Restarting service '%s' (restart #%d)", state.Hook.Name, restarts)

		// Wait a bit before restarting to avoid rapid restart loops
		time.Sleep(1 * time.Second)

		// Create a new command for the restart
		parts := strings.Fields(state.Hook.Service)
		cmd = e.createCommand(state.Hook, parts[0], parts[1:])
		cmd.Dir = state.Hook.WorkDir
		if cmd.Dir == "" {
			cmd.Dir = "/"
		}
	}
}

// isSuccessCode checks if an exit code is considered successful
func (e *Executor) isSuccessCode(hook *Hook, code int) bool {
	return slices.Contains(hook.SuccessCodes, code)
}

// GetExecution retrieves the execution state of a hook
func (e *Executor) GetExecution(hookName string) (*HookExecution, bool) {
	e.executionsMux.RLock()
	defer e.executionsMux.RUnlock()
	exec, exists := e.executions[hookName]
	return exec, exists
}

// GetAllExecutions returns all hook execution states
func (e *Executor) GetAllExecutions() map[string]*HookExecution {
	e.executionsMux.RLock()
	defer e.executionsMux.RUnlock()
	// Return a copy to avoid race conditions
	result := make(map[string]*HookExecution, len(e.executions))
	for k, v := range e.executions {
		result[k] = v
	}
	return result
}

// setExecution sets the execution state of a hook
func (e *Executor) setExecution(hookName string, execution *HookExecution) {
	e.executionsMux.Lock()
	defer e.executionsMux.Unlock()
	e.executions[hookName] = execution
}
