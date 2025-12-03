package hook

import (
	"sync"

	"penv/shared/proc"
)

// Global service registry to track services across executors
var (
	globalServices    = make(map[string]*ServiceState)
	globalServicesMux sync.RWMutex
)

// GetGlobalService retrieves a service from the global registry
func GetGlobalService(hookName string) (*ServiceState, bool) {
	globalServicesMux.RLock()
	defer globalServicesMux.RUnlock()
	service, exists := globalServices[hookName]
	return service, exists
}

// RegisterGlobalService registers a service in the global registry
func RegisterGlobalService(hookName string, service *ServiceState) {
	globalServicesMux.Lock()
	defer globalServicesMux.Unlock()
	globalServices[hookName] = service

	// Also add to proc.RunningPids (only if PID is set)
	pid := service.GetPID()
	if pid > 0 {
		proc.RunningPids.AddProcessId(pid)
	}
}

// UnregisterGlobalService removes a service from the global registry
func UnregisterGlobalService(hookName string) {
	globalServicesMux.Lock()
	defer globalServicesMux.Unlock()
	delete(globalServices, hookName)
}

// GetAllGlobalServices returns all active services
func GetAllGlobalServices() []*ServiceState {
	globalServicesMux.RLock()
	defer globalServicesMux.RUnlock()

	services := make([]*ServiceState, 0, len(globalServices))
	for _, service := range globalServices {
		if service.GetActive() {
			services = append(services, service)
		}
	}
	return services
}

// StopGlobalService stops a service by name
func StopGlobalService(hookName string, timeout int) error {
	service, exists := GetGlobalService(hookName)
	if !exists || !service.GetActive() {
		return nil
	}

	if err := proc.RunningPids.KillProcess(service.GetPID(), timeout); err != nil {
		return err
	}

	service.SetActive(false)
	UnregisterGlobalService(hookName)
	return nil
} // StopAllGlobalServices stops all registered services
func StopAllGlobalServices(timeout int) error {
	services := GetAllGlobalServices()
	for _, service := range services {
		if err := StopGlobalService(service.Hook.Name, timeout); err != nil {
			// Log but continue stopping other services
			continue
		}
	}
	return nil
}
