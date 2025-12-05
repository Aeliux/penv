package hook

import (
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strings"
	"sync"
	"time"

	"penv/shared/logger"
	"penv/shared/proc"
)

// Executor handles the execution of hooks
type Executor struct {
	manager        *Manager
	graph          *DependencyGraph
	executions     map[string]*HookExecution
	executionsMux  sync.RWMutex
	defaultWorkDir string
	mode           ExecutionMode
	trigger        Trigger
}

// NewExecutor creates a new hook executor
func NewExecutor(manager *Manager, graph *DependencyGraph, defaultWorkDir string, mode ExecutionMode, trigger Trigger) *Executor {
	if defaultWorkDir == "" {
		defaultWorkDir = "/"
	}

	return &Executor{
		manager:        manager,
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
	// Check version constraints
	if hook.PinitVersion != nil {
		if !hook.PinitVersion.Check(e.manager.pinitVersion) {
			execution := e.createExecution(hook, StatusSkipped)
			execution.EndTime = time.Now()
			execution.SkipReason = SkipReasonIncompatibleVersion
			e.setExecution(hook.Name, execution)
			logger.S.Warnf("Skipping hook '%s': requires pinit version %s, current version is %s", hook.Name, hook.PinitVersion.String(), e.manager.pinitVersion.String())
			return fmt.Errorf("requires pinit version %s", hook.PinitVersion.String())
		}
	}

	if hook.PenvVersion != nil {
		if !hook.PenvVersion.Check(e.manager.penvVersion) {
			execution := e.createExecution(hook, StatusSkipped)
			execution.EndTime = time.Now()
			execution.SkipReason = SkipReasonIncompatibleVersion
			e.setExecution(hook.Name, execution)
			logger.S.Warnf("Skipping hook '%s': requires penv version %s, current version is %s", hook.Name, hook.PenvVersion.String(), e.manager.penvVersion.String())
			return fmt.Errorf("requires penv version %s", hook.PenvVersion.String())
		}
	}

	// Check dependencies
	depStatuses := make(map[string]ExecutionStatus)
	for _, depName := range hook.RequiredHooks {
		depExec, exists := e.GetExecution(depName)
		if !exists {
			// Dependency not executed yet
			execution := e.createExecution(hook, StatusSkipped)
			execution.EndTime = time.Now()
			execution.SkipReason = SkipReasonDependencyMissing
			execution.Dependencies = depStatuses
			e.setExecution(hook.Name, execution)
			logger.S.Warnf("Skipping hook '%s': dependency '%s' not executed", hook.Name, depName)
			return fmt.Errorf("dependency '%s' not executed", depName)
		}

		depStatuses[depName] = depExec.Status

		// Check if dependency completed successfully
		if depExec.Status != StatusCompleted {
			execution := e.createExecution(hook, StatusSkipped)
			execution.EndTime = time.Now()
			execution.SkipReason = SkipReasonDependencyFailed
			execution.Dependencies = depStatuses
			e.setExecution(hook.Name, execution)
			logger.S.Warnf("Skipping hook '%s': dependency '%s' %s", hook.Name, depName, depExec.Status)
			return fmt.Errorf("dependency '%s' %s", depName, depExec.Status)
		}
	}

	// Check for single-run hooks
	if hook.SingleRun {
		reuse := true

		// Check service running
		if hook.RunType == RunTypeService {
			if _, exists := GetGlobalService(hook.Name); exists {
				logger.S.Infof("Hook '%s' is single-run service and is already running, skipping execution", hook.Name)
			} else {
				// Not running, proceed to execute
				reuse = false
			}
		}
		// Check if already run
		pastExec, exists := e.manager.singleRunHooks[hook.Name]
		if reuse && exists {
			logger.S.Infof("Hook '%s' is single-run and has already executed, reusing previous result", hook.Name)
			e.setExecution(hook.Name, &pastExec)
			return pastExec.Result.Error
		}
	}

	// Apply persistent environment variables
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
		execution := e.createExecution(hook, StatusCompleted)
		execution.EndTime = time.Now()
		e.setExecution(hook.Name, execution)
		return nil
	}

	execution := e.createExecution(hook, StatusRunning)
	execution.Dependencies = depStatuses
	e.setExecution(hook.Name, execution)
	logger.S.Infof("Executing hook: %s", hook.Name)

	var result *ExecutionResult
	switch hook.RunType {
	case RunTypeNormal:
		result = e.executeNormal(hook, execution)
	case RunTypeService:
		result = e.executeService(hook, execution)
	default:
		return fmt.Errorf("unsupported run type '%s' for hook '%s'", hook.RunType, hook.Name)
	}

	execution.EndTime = time.Now()
	execution.Result = result
	if result.Error != nil {
		execution.Status = StatusFailed
		logger.S.Errorf("Hook '%s' failed: %v", hook.Name, result.Error)
		return result.Error
	}

	execution.Status = StatusCompleted
	logger.S.Infof("Hook '%s' completed successfully", hook.Name)

	if hook.SingleRun {
		// Store in manager's single-run hooks
		e.manager.singleRunHooks[hook.Name] = *execution
	}

	return nil
}

func (e *Executor) prepareCommand(hook *Hook, conditionScript bool) (string, []string, error) {
	execFormat := hook.ExecFormat
	// trick: if preparing for condition script, always treat as script
	if conditionScript {
		execFormat = ExecFormatScript
	}

	if execFormat == ExecFormatUndefined {
		return "", nil, fmt.Errorf("undefined execution format for hook '%s'", hook.Name)
	}

	var command string
	var args []string

	switch execFormat {
	case ExecFormatScript:
		tmpFile, err := os.CreateTemp("", fmt.Sprintf("hook-%s-*", hook.Name))
		if err != nil {
			return "", nil, fmt.Errorf("failed to create temp script file: %w", err)
		}
		defer tmpFile.Close()

		scriptString := &hook.Exec
		if conditionScript {
			scriptString = &hook.ConditionScript
		}
		if _, err := tmpFile.WriteString(*scriptString); err != nil {
			return "", nil, fmt.Errorf("failed to write to temp script file: %w", err)
		}

		if err := tmpFile.Chmod(0755); err != nil {
			return "", nil, fmt.Errorf("failed to set execute permission on temp script file: %w", err)
		}

		command = tmpFile.Name()
		args = []string{}
	case ExecFormatCommand:
		parts := strings.Fields(hook.Exec)
		if len(parts) == 0 {
			return "", nil, fmt.Errorf("empty command in hook '%s'", hook.Name)
		}
		command = parts[0]
		args = parts[1:]
	default:
		return "", nil, fmt.Errorf("unsupported execution format '%s' for hook '%s'", execFormat, hook.Name)
	}

	return command, args, nil
}

// createCommand creates a configured exec.Cmd for a hook
func (e *Executor) createCommand(hook *Hook, conditionScript bool) (*exec.Cmd, error) {
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

	command, args, err := e.prepareCommand(hook, conditionScript)
	if err != nil {
		logger.S.Errorf("Failed to prepare command for hook '%s': %v", hook.Name, err)
		return nil, err
	}
	cmd := proc.GetCmd(command, args, env, nil, nil, nil)

	// Set working directory
	workDir := hook.WorkDir
	if workDir == "" {
		workDir = e.defaultWorkDir
	}
	cmd.Dir = workDir

	return cmd, nil
}

// runCommandWithWait executes a command and waits for completion, checking success codes
func (e *Executor) runCommandWithWait(cmd *exec.Cmd, hook *Hook, timeoutSeconds int) *ExecutionResult {
	// Start the command
	if err := cmd.Start(); err != nil {
		return &ExecutionResult{
			ExitCode: -1,
			Error:    fmt.Errorf("failed to start command: %w", err),
		}
	}

	// Channel to signal completion and capture exit code and error
	done := make(chan *ExecutionResult, 1)

	// Wait for command to complete in a separate goroutine
	go func() {
		err := cmd.Wait()
		exitCode := 0
		success := false
		if cmd.ProcessState != nil {
			exitCode = cmd.ProcessState.ExitCode()
			// Check if exit code is considered success
			if !e.isSuccessCode(hook, exitCode) {
				err = fmt.Errorf("command exited with code %d", exitCode)
			} else {
				err = nil
				success = true
			}
		}
		done <- &ExecutionResult{
			ExitCode:  exitCode,
			Error:     err,
			IsSuccess: success,
		}
	}()

	// Handle timeout if specified
	if timeoutSeconds > 0 {
		select {
		case res := <-done:
			return res
		case <-time.After(time.Duration(timeoutSeconds) * time.Second):
			// Timeout occurred, kill the process
			if err := cmd.Process.Kill(); err != nil {
				return &ExecutionResult{
					ExitCode: -1,
					Error:    fmt.Errorf("failed to kill process after timeout: %w", err),
				}
			}
			return &ExecutionResult{
				ExitCode:   -1,
				Error:      fmt.Errorf("command timed out after %d seconds", timeoutSeconds),
				IsTimedOut: true,
			}
		}
	} else {
		// No timeout, just wait for completion
		res := <-done
		return res
	}
}

// executeNormal executes a normal hook
func (e *Executor) executeNormal(hook *Hook, execution *HookExecution) *ExecutionResult {
	cmd, err := e.createCommand(hook, false)
	if err != nil {
		return &ExecutionResult{
			ExitCode: -1,
			Error:    fmt.Errorf("failed to create command: %w", err),
		}
	}

	if hook.ExecFormat == ExecFormatScript {
		logger.S.Infof("Executing script %s hook '%s' in %s", cmd.Args[0], hook.Name, cmd.Dir)
	} else {
		logger.S.Infof("Executing command %s hook '%s' in %s", cmd.Args, hook.Name, cmd.Dir)
	}

	return e.runCommandWithWait(cmd, hook, hook.TimeoutSeconds)
}

// executeService starts a service hook
func (e *Executor) executeService(hook *Hook, execution *HookExecution) *ExecutionResult {
	cmd, err := e.createCommand(hook, false)
	if err != nil {
		return &ExecutionResult{
			ExitCode: -1,
			Error:    fmt.Errorf("failed to create command: %w", err),
		}
	}

	logger.S.Infof("Starting service hook '%s' with command %s in %s", hook.Name, cmd.Args, cmd.Dir)

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
			return &ExecutionResult{
				ExitCode: -1,
				Error:    err,
			}
		}
		// Startup successful, register the service
		RegisterGlobalService(hook.Name, serviceState)
		return &ExecutionResult{
			ExitCode:  0,
			Error:     nil,
			IsSuccess: true,
		}
	case <-time.After(5 * time.Second):
		// Timeout waiting for service to start
		serviceState.SetActive(false)
		return &ExecutionResult{
			ExitCode:   -1,
			Error:      fmt.Errorf("service startup timed out"),
			IsTimedOut: true,
		}
	}
}

// manageService handles service lifecycle including restarts
func (e *Executor) manageService(cmd *exec.Cmd, state *ServiceState, startupDone chan error) {
	firstStart := true
	defer func() {
		state.SetActive(false)
		UnregisterGlobalService(state.Hook.Name)
	}()

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
		// Register PID after first successful start
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
			return
		}

		// Check if restart is enabled
		if state.Hook.RestartCount <= 0 {
			logger.S.Errorf("Service '%s' failed and restart is disabled", state.Hook.Name)
			return
		}

		// Check restart limit
		restarts := state.GetRestarts()
		if restarts >= state.Hook.RestartCount {
			logger.S.Errorf("Service '%s' reached maximum restart attempts (%d), not restarting", state.Hook.Name, restarts)
			return
		}

		// Restart the service
		restarts = state.IncrementRestarts()
		logger.S.Infof("Restarting service '%s' (restart #%d)", state.Hook.Name, restarts)

		// Wait a bit before restarting to avoid rapid restart loops
		time.Sleep(1 * time.Second)

		// Create a new command for the restart
		cmd, err = e.createCommand(state.Hook, false)
		if err != nil {
			logger.S.Errorf("Failed to create command for restarting service '%s': %v", state.Hook.Name, err)
			return
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

// createExecution creates a base HookExecution with common fields
func (e *Executor) createExecution(hook *Hook, status ExecutionStatus) *HookExecution {
	return &HookExecution{
		Hook:      hook,
		Status:    status,
		StartTime: time.Now(),
		Mode:      e.mode,
		Trigger:   e.trigger,
	}
}
