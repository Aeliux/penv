package hook

import (
	"sync"
	"time"

	"github.com/hashicorp/go-version"
)

// ExecutionMode represents the mode in which hooks can run
type ExecutionMode string

// Trigger represents when a hook should be executed
type Trigger string

// RunType indicates what type of execution the hook performs
type RunType string

const (
	RunTypeNormal  RunType = "normal"  // Run once and capture exit code
	RunTypeService RunType = "service" // Run as a long-running service
)

// ExecFormat indicates how the hook is executed
type ExecFormat string

const (
	ExecFormatUndefined ExecFormat = ""        // Undefined exec format
	ExecFormatCommand   ExecFormat = "command" // Single command execution
	ExecFormatScript    ExecFormat = "script"  // Script execution
)

type EnvVariable struct {
	Key   string
	Value string
}

// Hook represents a parsed hook configuration
type Hook struct {
	// Metadata
	Name         string               // Unique name of the hook
	Description  string               // Optional description of the hook
	Version      *version.Version     // Optional version of the hook
	Author       string               // Optional author of the hook
	PinitVersion *version.Constraints // Pinit version constraint
	Requires     []string             // Dependencies on other hooks
	SuccessCodes []int                // Exit codes considered successful
	SingleRun    bool                 // If true, the hook will only run once per pinit execution

	// Conditions
	ConditionScript string               // Script that must return 0 to run the hook
	PenvVersion     *version.Constraints // Penv version constraint
	Modes           []string             // Modes where hook will execute
	Triggers        []string             // Triggers for hook execution

	// Execution configuration
	Exec       string     // Command or script to execute
	ExecFormat ExecFormat // Format of execution
	RunType    RunType    // Type of execution
	WorkDir    string     // Working directory

	// Environment variables
	PersistentEnv []EnvVariable // [env] - Updates proc.EnvironmentVariables, affects all future processes
	RunEnv        []EnvVariable // [run.env] - Only for this hook's execution

	// Normal run options
	TimeoutSeconds int // Timeout for normal hooks

	// Service options
	RestartCount int // Number of restarts for service hooks

	// Runtime state
	FilePath string // Path to the hook file
}

// ExecutionStatus represents the current state of a hook execution
type ExecutionStatus string

const (
	StatusPending   ExecutionStatus = "pending"
	StatusRunning   ExecutionStatus = "running"
	StatusCompleted ExecutionStatus = "completed"
	StatusFailed    ExecutionStatus = "failed"
	StatusSkipped   ExecutionStatus = "skipped"
)

type SkipReason string

const (
	SkipReasonDependencyFailed SkipReason = "dependency_failed"
	SkipReasonConditionNotMet  SkipReason = "condition_not_met"
)

// HookExecution represents the runtime state of a hook
type HookExecution struct {
	Hook         *Hook
	Status       ExecutionStatus
	Mode         ExecutionMode
	Trigger      Trigger
	StartTime    time.Time
	EndTime      time.Time
	Error        error
	PID          int                        // For service hooks
	ExitCode     int                        // Exit code of the hook process
	SkipReason   SkipReason                 // Reason why hook was skipped
	Dependencies map[string]ExecutionStatus // Status of dependencies
}

// ServiceState tracks a running service
type ServiceState struct {
	Hook      *Hook
	pid       int
	StartTime time.Time
	restarts  int
	active    bool
	mux       sync.RWMutex // Protects all fields for concurrent access
}

// Thread-safe getters and setters
func (s *ServiceState) GetPID() int {
	s.mux.RLock()
	defer s.mux.RUnlock()
	return s.pid
}

func (s *ServiceState) SetPID(pid int) {
	s.mux.Lock()
	defer s.mux.Unlock()
	s.pid = pid
}

func (s *ServiceState) GetActive() bool {
	s.mux.RLock()
	defer s.mux.RUnlock()
	return s.active
}

func (s *ServiceState) SetActive(active bool) {
	s.mux.Lock()
	defer s.mux.Unlock()
	s.active = active
}

func (s *ServiceState) GetRestarts() int {
	s.mux.RLock()
	defer s.mux.RUnlock()
	return s.restarts
}

func (s *ServiceState) IncrementRestarts() int {
	s.mux.Lock()
	defer s.mux.Unlock()
	s.restarts++
	return s.restarts
}
