package hook

import (
	"fmt"
	"os"
	"path/filepath"

	"penv/shared/logger"
)

// Manager provides a high-level API for hook management
type Manager struct {
	mode           ExecutionMode
	allHooks       *DependencyGraph
	parser         *Parser
	executor       *Executor
	defaultWorkDir string
}

// NewManager creates a new hook manager with a specific mode and hook directory
func NewManager(mode ExecutionMode, hookDir string, defaultWorkDir string) *Manager {
	m := &Manager{
		mode:           mode,
		allHooks:       NewDependencyGraph(),
		parser:         NewParser(mode),
		defaultWorkDir: defaultWorkDir,
	}

	// Load hooks immediately if directory exists
	if err := m.loadHooks(hookDir); err != nil {
		logger.S.Errorf("Failed to load hooks: %v", err)
	}

	return m
}

// loadHooks loads all hooks from the specified directory
func (m *Manager) loadHooks(dir string) error {
	// Check if directory exists
	if _, err := os.Stat(dir); os.IsNotExist(err) {
		logger.S.Debugf("Hook directory does not exist: %s (skipping)", dir)
		return nil
	}

	logger.S.Infof("Loading hooks from: %s (mode: %s)", dir, m.mode)

	hooks, err := m.parser.ParseDirectory(dir)
	if err != nil {
		return fmt.Errorf("failed to parse hooks: %w", err)
	}

	for _, hook := range hooks {
		if err := m.allHooks.AddHook(hook); err != nil {
			return fmt.Errorf("failed to add hook '%s': %w", hook.Name, err)
		}
		logger.S.Debugf("Loaded hook: %s (from %s)", hook.Name, filepath.Base(hook.FilePath))
	}

	// Validate the complete dependency graph
	if err := m.allHooks.Validate(); err != nil {
		return fmt.Errorf("hook validation failed: %w", err)
	}

	logger.S.Infof("Loaded %d hook(s) for mode '%s'", len(m.allHooks.GetAllHooks()), m.mode)
	return nil
}

// ExecuteTrigger executes all hooks for a given trigger
func (m *Manager) ExecuteTrigger(trigger Trigger) error {
	logger.S.Infof("Executing trigger: %s (mode: %s)", trigger, m.mode)

	// Filter hooks by trigger (mode already filtered during parsing)
	filtered := m.allHooks.FilterByTrigger(trigger)

	hooks := filtered.GetAllHooks()
	if len(hooks) == 0 {
		logger.S.Infof("No hooks to execute for trigger '%s'", trigger)
		return nil
	}

	logger.S.Infof("Found %d hook(s) for trigger '%s'", len(hooks), trigger)

	// Get execution order
	batches, err := filtered.TopologicalSort()
	if err != nil {
		return fmt.Errorf("failed to sort hooks: %w", err)
	}

	logger.S.Infof("Execution plan: %d batch(es)", len(batches))

	// Create executor and execute batches
	m.executor = NewExecutor(filtered, m.defaultWorkDir, m.mode, trigger)
	if err := m.executor.ExecuteBatches(batches); err != nil {
		return fmt.Errorf("hook execution failed: %w", err)
	}

	logger.S.Infof("Trigger '%s' completed successfully", trigger)
	return nil
}

// StopAllServices stops all running services
func (m *Manager) StopAllServices(timeout int) error {
	if m.executor == nil {
		return nil
	}

	return m.executor.StopAllServices(timeout)
}

// GetActiveServices returns all currently active services
func (m *Manager) GetActiveServices() []*ServiceState {
	if m.executor == nil {
		return []*ServiceState{}
	}

	return m.executor.GetAllServices()
}

// GetHookExecution returns the execution state of a specific hook
func (m *Manager) GetHookExecution(hookName string) (*HookExecution, bool) {
	if m.executor == nil {
		return nil, false
	}

	return m.executor.GetExecution(hookName)
}

// GetAllExecutions returns all hook execution states
func (m *Manager) GetAllExecutions() map[string]*HookExecution {
	if m.executor == nil {
		return make(map[string]*HookExecution)
	}

	return m.executor.GetAllExecutions()
}

// GetAllHooks returns all loaded hooks
func (m *Manager) GetAllHooks() []*Hook {
	return m.allHooks.GetAllHooks()
}

// GetHooksForTrigger returns hooks that would execute for a given trigger
func (m *Manager) GetHooksForTrigger(trigger Trigger) []*Hook {
	filtered := m.allHooks.FilterByTrigger(trigger)
	return filtered.GetAllHooks()
}

// GetMode returns the current execution mode
func (m *Manager) GetMode() ExecutionMode {
	return m.mode
}

// ValidateHooks validates all loaded hooks
func (m *Manager) ValidateHooks() error {
	return m.allHooks.Validate()
}
