package proc

import (
	"os"
	"sync"
)

type EnvironmentMap struct {
	mu   sync.RWMutex
	vars map[string]string
}

// EnvironmentVariables holds the environment variables for child processes.
// It is initialized with the current process's environment variables.
// It's dedicated from os.Environ to allow modifications without affecting the parent process.
var EnvironmentVariables = EnvironmentMap{vars: make(map[string]string)}

func NewEnvironmentMap() *EnvironmentMap {
	return &EnvironmentMap{
		vars: make(map[string]string),
	}
}

func (e *EnvironmentMap) Len() int {
	e.mu.RLock()
	defer e.mu.RUnlock()
	return len(e.vars)
}

func (e *EnvironmentMap) Copy() *EnvironmentMap {
	e.mu.RLock()
	defer e.mu.RUnlock()
	newMap := make(map[string]string)
	for k, v := range e.vars {
		newMap[k] = v
	}
	return &EnvironmentMap{vars: newMap}
}

func (e *EnvironmentMap) Set(key, value string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	e.vars[key] = value
}

func (e *EnvironmentMap) Get(key string) (string, bool) {
	e.mu.RLock()
	defer e.mu.RUnlock()
	value, exists := e.vars[key]
	return value, exists
}

func (e *EnvironmentMap) Delete(key string) {
	e.mu.Lock()
	defer e.mu.Unlock()
	delete(e.vars, key)
}

func (e *EnvironmentMap) ToSlice() []string {
	e.mu.RLock()
	defer e.mu.RUnlock()
	var envSlice []string
	for key, value := range e.vars {
		envSlice = append(envSlice, key+"="+value)
	}
	return envSlice
}

// ResetEnvironments initializes the EnvironmentVariables map with the current
// process's environment variables.
func ResetEnvironments() {
	EnvironmentVariables.mu.Lock()
	defer EnvironmentVariables.mu.Unlock()
	for _, env := range os.Environ() {
		// Split environment variable into key and value
		for i := 0; i < len(env); i++ {
			if env[i] == '=' {
				key := env[:i]
				value := env[i+1:]
				EnvironmentVariables.vars[key] = value
				break
			}
		}
	}
}
