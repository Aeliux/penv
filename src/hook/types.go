package hook

import (
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

// Hook represents a parsed hook configuration
type Hook struct {
	// Metadata
	Name        string
	Description string
	Version     string
	Author      string

	// Dependencies and constraints
	Requires      []string           // Other hooks required before this one
	RequiresPinit []*version.Version // Pinit version constraints (>=3, <4, etc.)
	Modes         []string           // Modes where hook will execute (flexible)
	Triggers      []string           // Triggers for hook execution (flexible)

	// Execution configuration
	RunType RunType
	Command string // For command execution
	Shell   string // For shell script execution
	Service string // For service execution
	WorkDir string // Working directory

	// Environment variables
	PersistentEnv map[string]string // [env] - Updates proc.EnvironmentVariables, affects all future processes
	RunEnv        map[string]string // [run.env] - Only for this hook's execution

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

// HookExecution represents the runtime state of a hook
type HookExecution struct {
	Hook         *Hook
	Status       ExecutionStatus
	StartTime    time.Time
	EndTime      time.Time
	Error        error
	PID          int                        // For service hooks
	ExitCode     int                        // Exit code of the hook process
	SkipReason   string                     // Reason why hook was skipped
	Dependencies map[string]ExecutionStatus // Status of dependencies
}

// ServiceState tracks a running service
type ServiceState struct {
	Hook      *Hook
	PID       int
	StartTime time.Time
	Restarts  int
	Active    bool
}
