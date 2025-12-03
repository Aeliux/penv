package hook

import (
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"slices"
	"strings"
	"sync"
	"syscall"
	"time"

	"penv/shared/logger"
	"penv/shared/proc"
)

// Executor handles the execution of hooks
type Executor struct {
	graph          *DependencyGraph
	executions     map[string]*HookExecution
	executionsMux  sync.RWMutex
	services       map[string]*ServiceState
	servicesMux    sync.RWMutex
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
		services:       make(map[string]*ServiceState),
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
	// Apply persistent environment variables to proc.EnvironmentVariables FIRST
	// This happens before dependency checking so env-only hooks can affect their dependents
	if len(hook.PersistentEnv) > 0 {
		logger.S.Debugf("Applying %d persistent environment variables from hook '%s'", len(hook.PersistentEnv), hook.Name)

		// To support variable expansion that references other vars in same section,
		// we apply vars in multiple passes. Each var can reference previously applied vars.
		applied := make(map[string]string)
		maxPasses := 10 // Prevent infinite loops

		for pass := 0; pass < maxPasses; pass++ {
			changed := false
			for key, value := range hook.PersistentEnv {
				// Skip if already fully applied (no more $ signs)
				if appliedVal, exists := applied[key]; exists && !strings.Contains(appliedVal, "$") {
					continue
				}

				// Expand using empty envMap so it checks proc.EnvironmentVariables
				// This allows vars in this section to reference each other
				expandedValue := expandEnvVars(value, nil)
				if applied[key] != expandedValue {
					applied[key] = expandedValue
					proc.EnvironmentVariables.Set(key, expandedValue)
					changed = true
					logger.S.Debugf("  %s=%s (pass %d)", key, expandedValue, pass+1)
				}
			}
			if !changed {
				break
			}
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
		err, exCode = e.executeCommand(hook, execution)
	case RunTypeShell:
		err, exCode = e.executeShell(hook, execution)
	case RunTypeService:
		err, exCode = e.executeService(hook, execution)
	default:
		err = fmt.Errorf("unknown run type: %s", hook.RunType)
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

// buildHookEnv creates environment variables for hook execution
// These are process-specific and don't affect proc.EnvironmentVariables
func (e *Executor) buildHookEnv(hook *Hook) map[string]string {
	env := make(map[string]string)

	// Copy hook's run-only environment variables and expand them
	for key, value := range hook.RunEnv {
		env[key] = expandEnvVars(value, hook.RunEnv)
	}

	// Add PINIT_HOOK_* variables
	env["PINIT_HOOK"] = hook.Name
	env["PINIT_HOOK_PATH"] = hook.FilePath
	env["PINIT_HOOK_MODE"] = string(e.mode)
	env["PINIT_HOOK_TRIGGER"] = string(e.trigger)

	return env
}

// executeCommand executes a command hook
func (e *Executor) executeCommand(hook *Hook, execution *HookExecution) (error, int) {
	// Parse command and arguments
	parts := strings.Fields(hook.Command)
	if len(parts) == 0 {
		return fmt.Errorf("empty command"), -1
	}

	cmd := proc.GetCmd(parts[0], parts[1:], e.buildHookEnv(hook), nil, nil, nil)

	// Set working directory
	workDir := hook.WorkDir
	if workDir == "" {
		workDir = e.defaultWorkDir
	}
	cmd.Dir = workDir

	logger.S.Debugf("Running command: %s (workdir: %s)", hook.Command, workDir)

	// Run command and wait for completion
	if err := cmd.Run(); err != nil {
		if cmd.ProcessState != nil {
			exitCode := cmd.ProcessState.ExitCode()
			if !e.isSuccessCode(hook, exitCode) {
				return fmt.Errorf("command exited with non-success code: %d", exitCode), exitCode
			}
		} else {
			return fmt.Errorf("command failed: %w", err), -1
		}
	}

	return nil, 0
}

// executeShell executes a shell script hook
func (e *Executor) executeShell(hook *Hook, execution *HookExecution) (error, int) {
	// Create a temporary script file
	tmpDir := os.TempDir()
	scriptPath := filepath.Join(tmpDir, fmt.Sprintf("hook-%s-%d.sh", hook.Name, time.Now().UnixNano()))

	if err := os.WriteFile(scriptPath, []byte(hook.Shell), 0755); err != nil {
		return fmt.Errorf("failed to create script file: %w", err), -1
	}
	defer os.Remove(scriptPath)

	// Execute the script
	cmd := proc.GetCmd(scriptPath, []string{}, e.buildHookEnv(hook), nil, nil, nil)

	// Set working directory
	workDir := hook.WorkDir
	if workDir == "" {
		workDir = e.defaultWorkDir
	}
	cmd.Dir = workDir

	logger.S.Debugf("Running shell script for hook: %s (workdir: %s)", hook.Name, workDir)

	// Run script and wait for completion
	if err := cmd.Run(); err != nil {
		if cmd.ProcessState != nil {
			exitCode := cmd.ProcessState.ExitCode()
			if !e.isSuccessCode(hook, exitCode) {
				return fmt.Errorf("shell script exited with non-success code: %d", exitCode), exitCode
			}
		} else {
			return fmt.Errorf("shell script failed: %w", err), -1
		}
	}

	return nil, 0
}

// executeService starts a service hook
func (e *Executor) executeService(hook *Hook, execution *HookExecution) (error, int) {
	// Parse service command and arguments
	parts := strings.Fields(hook.Service)
	if len(parts) == 0 {
		return fmt.Errorf("empty service command"), -1
	}

	cmd := proc.GetCmd(parts[0], parts[1:], e.buildHookEnv(hook), nil, nil, nil)

	// Set working directory
	workDir := hook.WorkDir
	if workDir == "" {
		workDir = e.defaultWorkDir
	}
	cmd.Dir = workDir

	logger.S.Infof("Starting service: %s (workdir: %s)", hook.Service, workDir)

	// Start the service process
	serviceState := &ServiceState{
		Hook:      hook,
		StartTime: time.Now(),
		Active:    true,
	}

	// Start process in background with restart handling
	go e.manageService(cmd, serviceState)

	// Give the service a moment to start
	time.Sleep(100 * time.Millisecond)

	// Check if service is still running
	if !serviceState.Active {
		return fmt.Errorf("service failed to start"), -1
	}

	e.setService(hook.Name, serviceState)
	execution.PID = serviceState.PID

	return nil, 0
}

// manageService handles service lifecycle including restarts
func (e *Executor) manageService(cmd *exec.Cmd, state *ServiceState) {
	for {
		err := cmd.Start()
		if err != nil {
			logger.S.Errorf("Service '%s' failed to start: %v", state.Hook.Name, err)
			state.Active = false
			return
		}

		state.PID = cmd.Process.Pid
		proc.RunningPids.AddProcess(cmd.Process)

		logger.S.Infof("Service '%s' started with PID %d", state.Hook.Name, state.PID)

		// Wait for process to exit
		cmd.Wait()

		exitCode := 0
		if cmd.ProcessState != nil {
			exitCode = cmd.ProcessState.ExitCode()
		}

		logger.S.Warnf("Service '%s' (PID %d) exited with code %d", state.Hook.Name, state.PID, exitCode)

		// Check if exit code is considered success
		if e.isSuccessCode(state.Hook, exitCode) {
			logger.S.Infof("Service '%s' exited successfully", state.Hook.Name)
			state.Active = false
			return
		}

		// Check if restart is enabled
		if !state.Hook.Restart {
			logger.S.Errorf("Service '%s' failed and restart is disabled", state.Hook.Name)
			state.Active = false
			return
		}

		// Check restart limit
		if state.Restarts >= 10 {
			logger.S.Errorf("Service '%s' reached maximum restart attempts (%d), not restarting", state.Hook.Name, state.Restarts)
			state.Active = false
			return
		}

		// Restart the service
		state.Restarts++
		logger.S.Infof("Restarting service '%s' (restart #%d)", state.Hook.Name, state.Restarts)

		// Wait a bit before restarting to avoid rapid restart loops
		time.Sleep(1 * time.Second)

		// Create a new command for the restart
		parts := strings.Fields(state.Hook.Service)
		cmd = proc.GetCmd(parts[0], parts[1:], e.buildHookEnv(state.Hook), nil, nil, nil)
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

// StopAllServices gracefully stops all running services
func (e *Executor) StopAllServices(timeout int) error {
	e.servicesMux.RLock()
	services := make([]*ServiceState, 0, len(e.services))
	for _, service := range e.services {
		if service.Active {
			services = append(services, service)
		}
	}
	e.servicesMux.RUnlock()

	logger.S.Infof("Stopping %d service(s)", len(services))

	for _, service := range services {
		if err := e.stopService(service, timeout); err != nil {
			logger.S.Errorf("Failed to stop service '%s': %v", service.Hook.Name, err)
		}
	}

	return nil
}

// stopService stops a single service
func (e *Executor) stopService(service *ServiceState, timeout int) error {
	if !service.Active || service.PID == 0 {
		return nil
	}

	logger.S.Infof("Stopping service '%s' (PID %d)", service.Hook.Name, service.PID)

	process, err := os.FindProcess(service.PID)
	if err != nil {
		return fmt.Errorf("failed to find process: %w", err)
	}

	// Send SIGTERM for graceful shutdown
	if err := process.Signal(syscall.SIGTERM); err != nil {
		return fmt.Errorf("failed to send SIGTERM: %w", err)
	}

	// Wait for process to exit
	done := make(chan error, 1)
	go func() {
		_, err := process.Wait()
		done <- err
	}()

	select {
	case <-done:
		logger.S.Infof("Service '%s' stopped gracefully", service.Hook.Name)
		service.Active = false
		return nil
	case <-time.After(time.Duration(timeout) * time.Second):
		// Timeout exceeded, force kill
		logger.S.Warnf("Service '%s' did not stop gracefully, force killing", service.Hook.Name)
		if err := process.Kill(); err != nil {
			return fmt.Errorf("failed to kill process: %w", err)
		}
		service.Active = false
		return nil
	}
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

// GetService retrieves a service state
func (e *Executor) GetService(hookName string) (*ServiceState, bool) {
	e.servicesMux.RLock()
	defer e.servicesMux.RUnlock()
	service, exists := e.services[hookName]
	return service, exists
}

// setService sets a service state
func (e *Executor) setService(hookName string, service *ServiceState) {
	e.servicesMux.Lock()
	defer e.servicesMux.Unlock()
	e.services[hookName] = service
}

// GetAllServices returns all active services
func (e *Executor) GetAllServices() []*ServiceState {
	e.servicesMux.RLock()
	defer e.servicesMux.RUnlock()

	services := make([]*ServiceState, 0, len(e.services))
	for _, service := range e.services {
		if service.Active {
			services = append(services, service)
		}
	}
	return services
}
