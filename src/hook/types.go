package hook

import (
	"sync"
	"time"

	"github.com/hashicorp/go-version"
)

// ExecutionMode represents the mode in which hooks can run
// It's a flexible string type - you can use any mode name you want
type ExecutionMode string

// Trigger represents when a hook should be executed
// It's a flexible string type - you can use any trigger name you want
type Trigger string

// RunType indicates what type of execution the hook performs
type RunType string

const (
	RunTypeCommand RunType = "command"
	RunTypeShell   RunType = "shell"
	RunTypeService RunType = "service"
)

type EnvVariable struct {
	Key   string
	Value string
}

// Hook represents a parsed hook configuration
type Hook struct {
	// Metadata
	Name        string
	Description string
	Version     string
	Author      string

	// Dependencies and constraints
	Requires      []string           // Other hooks required before this one
	RequiresPinit *version.Constraints // Pinit version constraint
	Modes         []string           // Modes where hook will execute (flexible)
	Triggers      []string           // Triggers for hook execution (flexible)

	// Execution configuration
	RunType RunType
	Command string // For command execution
	Shell   string // For shell script execution
	Service string // For service execution
	WorkDir string // Working directory

	// Environment variables
	PersistentEnv []EnvVariable // [env] - Updates proc.EnvironmentVariables, affects all future processes
	RunEnv        []EnvVariable // [run.env] - Only for this hook's execution

	// Service options
	Restart      bool  // Whether to restart service if it fails
	SuccessCodes []int // Exit codes considered successful

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
