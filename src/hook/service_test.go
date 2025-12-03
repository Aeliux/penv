package hook

import (
	"os"
	"path/filepath"
	"syscall"
	"testing"
	"time"

	"penv/shared/proc"
)

func TestServiceBasicStartStop(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	hookContent := `
[hook]
name=test-service
mode=test
trigger=start

[run]
service=sleep 30
`

	hookFile := filepath.Join(tmpDir, "service.hook")
	if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
		t.Fatalf("Failed to create hook file: %v", err)
	}

	manager := NewManager(ExecutionMode("test"), tmpDir, tmpDir)

	// Start the service
	executor, err := manager.ExecuteTrigger(Trigger("start"))
	if err != nil {
		t.Fatalf("Failed to execute trigger: %v", err)
	}
	if executor == nil {
		t.Fatal("Executor should not be nil")
	}

	// Verify service is registered
	service, exists := GetGlobalService("test-service")
	if !exists {
		t.Fatal("Service should be registered in global registry")
	}
	if !service.GetActive() {
		t.Error("Service should be active")
	}
	if service.GetPID() == 0 {
		t.Errorf("Service PID should be set, got %d", service.GetPID())
	}
	t.Logf("Service PID: %d", service.GetPID())

	// Verify execution state
	exec, exists := executor.GetExecution("test-service")
	if !exists {
		t.Fatal("Execution should be tracked")
	}
	if exec.PID == 0 {
		t.Error("Execution PID should be set")
	}
	if exec.PID != service.GetPID() {
		t.Errorf("Execution PID (%d) should match service PID (%d)", exec.PID, service.GetPID())
	}

	// Verify process is actually running
	if !isProcessRunning(service.GetPID()) {
		t.Error("Service process should be running")
	}

	// Stop the service
	if err := StopGlobalService("test-service", 5); err != nil {
		t.Errorf("Failed to stop service: %v", err)
	}

	// Verify service is stopped
	time.Sleep(100 * time.Millisecond)
	if isProcessRunning(service.GetPID()) {
		t.Error("Service process should be stopped")
	}

	// Verify service is unregistered
	_, exists = GetGlobalService("test-service")
	if exists {
		t.Error("Service should be unregistered after stop")
	}
}

func TestServiceNoDuplicateStart(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	hookContent := `
[hook]
name=duplicate-service
mode=test
trigger=start

[run]
service=sleep 30
`

	hookFile := filepath.Join(tmpDir, "service.hook")
	if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
		t.Fatalf("Failed to create hook file: %v", err)
	}

	manager := NewManager(ExecutionMode("test"), tmpDir, tmpDir)

	// Start the service first time
	executor1, err := manager.ExecuteTrigger(Trigger("start"))
	if err != nil {
		t.Fatalf("Failed to execute trigger first time: %v", err)
	}

	service1, _ := GetGlobalService("duplicate-service")
	pid1 := service1.GetPID()

	// Try to start the service again
	executor2, err := manager.ExecuteTrigger(Trigger("start"))
	if err != nil {
		t.Fatalf("Failed to execute trigger second time: %v", err)
	}

	service2, _ := GetGlobalService("duplicate-service")
	pid2 := service2.GetPID()

	// Should be the same PID
	if pid1 != pid2 {
		t.Errorf("Service should not be restarted. PID1=%d, PID2=%d", pid1, pid2)
	}

	// Verify only one process is running
	if !isProcessRunning(pid1) {
		t.Error("Original service process should still be running")
	}

	// Both executors should report the same PID
	exec1, _ := executor1.GetExecution("duplicate-service")
	exec2, _ := executor2.GetExecution("duplicate-service")
	if exec1.PID != exec2.PID {
		t.Errorf("Both executions should report same PID: %d vs %d", exec1.PID, exec2.PID)
	}

	// Cleanup
	StopGlobalService("duplicate-service", 5)
}

func TestServiceRestart(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	// Create a script that fails quickly
	scriptPath := filepath.Join(tmpDir, "failing-service.sh")
	scriptContent := `#!/bin/bash
exit 1
`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("Failed to create script: %v", err)
	}

	hookContent := `
[hook]
name=restart-service
mode=test
trigger=start

[run]
service=` + scriptPath + `

[run.service]
restart=true
`

	hookFile := filepath.Join(tmpDir, "service.hook")
	if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
		t.Fatalf("Failed to create hook file: %v", err)
	}

	manager := NewManager(ExecutionMode("test"), tmpDir, tmpDir)

	executor, err := manager.ExecuteTrigger(Trigger("start"))
	if err != nil {
		t.Fatalf("Failed to execute trigger: %v", err)
	}

	// Service should be registered
	service, exists := GetGlobalService("restart-service")
	if !exists {
		t.Fatal("Service should be registered")
	}

	// Check the hook's restart flag
	t.Logf("Hook restart flag: %v", service.Hook.Restart)

	// Wait for service to fail and restart a few times
	time.Sleep(3 * time.Second)

	// Check that restarts happened
	t.Logf("Service restarts: %d, active: %v", service.GetRestarts(), service.GetActive())
	if service.GetRestarts() == 0 {
		t.Error("Service should have restarted at least once")
	}

	if service.GetRestarts() > 10 {
		t.Error("Service should not exceed max restart limit")
	}

	// Eventually it should stop after max restarts (wait longer for 10 restarts at 1s each)
	time.Sleep(10 * time.Second)
	if service.GetActive() {
		t.Errorf("Service should eventually stop after max restarts, but still active with %d restarts", service.GetRestarts())
	}

	// Verify execution tracked the service
	exec, _ := executor.GetExecution("restart-service")
	if exec.PID == 0 {
		t.Error("Execution should have tracked at least one PID")
	}
}

func TestServiceNoRestart(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	// Create a script that fails quickly
	scriptPath := filepath.Join(tmpDir, "failing-no-restart.sh")
	scriptContent := `#!/bin/bash
exit 1
`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("Failed to create script: %v", err)
	}

	hookContent := `
[hook]
name=no-restart-service
mode=test
trigger=start

[run]
service=` + scriptPath + `

[run.service]
restart=false
`

	hookFile := filepath.Join(tmpDir, "service.hook")
	if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
		t.Fatalf("Failed to create hook file: %v", err)
	}

	manager := NewManager(ExecutionMode("test"), tmpDir, tmpDir)

	executor, err := manager.ExecuteTrigger(Trigger("start"))
	if err != nil {
		t.Fatalf("Failed to execute trigger: %v", err)
	}

	// Service should be registered briefly
	service, exists := GetGlobalService("no-restart-service")
	if !exists {
		t.Fatal("Service should be registered")
	}

	// Wait for service to fail
	time.Sleep(2 * time.Second)

	// Should not restart
	if service.GetRestarts() > 0 {
		t.Error("Service should not restart when restart=false")
	}

	if service.GetActive() {
		t.Error("Service should be inactive after failure with restart=false")
	}

	// Verify execution tracked the service
	exec, _ := executor.GetExecution("no-restart-service")
	if exec.Status != StatusCompleted {
		t.Errorf("Expected status completed, got %s", exec.Status)
	}
}

func TestServiceSuccessCode(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	// Create a script that exits with code 5
	scriptPath := filepath.Join(tmpDir, "success-code.sh")
	scriptContent := `#!/bin/bash
exit 5
`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("Failed to create script: %v", err)
	}

	hookContent := `
[hook]
name=success-code-service
mode=test
trigger=start

[run]
service=` + scriptPath + `

[run.service]
success-codes=0,5
`

	hookFile := filepath.Join(tmpDir, "service.hook")
	if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
		t.Fatalf("Failed to create hook file: %v", err)
	}

	manager := NewManager(ExecutionMode("test"), tmpDir, tmpDir)

	executor, err := manager.ExecuteTrigger(Trigger("start"))
	if err != nil {
		t.Fatalf("Failed to execute trigger: %v", err)
	}

	// Wait for service to exit with code 5
	time.Sleep(2 * time.Second)

	// Should not be active (exited successfully and unregistered)
	service, exists := GetGlobalService("success-code-service")
	if exists && service.GetActive() {
		t.Error("Service should exit successfully with code 5 and be unregistered")
	}

	if exists && service.GetRestarts() > 0 {
		t.Error("Service should not restart when exit code is in success_codes")
	}

	// Verify execution completed successfully
	exec, _ := executor.GetExecution("success-code-service")
	if exec.Status != StatusCompleted {
		t.Errorf("Expected status completed, got %s", exec.Status)
	}
}

func TestStopAllServices(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	// Create multiple service hooks
	for i := 1; i <= 3; i++ {
		hookContent := `
[hook]
name=multi-service-` + string(rune('0'+i)) + `
mode=test
trigger=start

[run]
service=sleep 30
`
		hookFile := filepath.Join(tmpDir, "service"+string(rune('0'+i))+".hook")
		if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
			t.Fatalf("Failed to create hook file %d: %v", i, err)
		}
	}

	manager := NewManager(ExecutionMode("test"), tmpDir, tmpDir)

	_, err := manager.ExecuteTrigger(Trigger("start"))
	if err != nil {
		t.Fatalf("Failed to execute trigger: %v", err)
	}

	// Verify all services started
	services := GetAllGlobalServices()
	if len(services) != 3 {
		t.Errorf("Expected 3 services, got %d", len(services))
	}

	// Collect PIDs
	pids := make([]int, 0)
	for _, service := range services {
		pid := service.GetPID()
		if pid > 0 {
			pids = append(pids, pid)
		}
	}

	if len(pids) != 3 {
		t.Errorf("Expected 3 PIDs, got %d", len(pids))
	}

	// Stop all services
	if err := StopAllGlobalServices(5); err != nil {
		t.Errorf("Failed to stop all services: %v", err)
	}

	// Wait a bit for processes to terminate
	time.Sleep(500 * time.Millisecond)

	// Verify all processes are stopped
	for _, pid := range pids {
		if isProcessRunning(pid) {
			t.Errorf("Process %d should be stopped", pid)
		}
	}

	// Verify no active services remain
	remainingServices := GetAllGlobalServices()
	if len(remainingServices) > 0 {
		t.Errorf("Expected no active services, got %d", len(remainingServices))
	}
}

func TestServiceWithEnvironmentVariables(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	outputFile := filepath.Join(tmpDir, "service-output.txt")

	// Create a script that writes env var to file
	scriptPath := filepath.Join(tmpDir, "env-service.sh")
	scriptContent := `#!/bin/bash
echo "SERVICE_VAR=$SERVICE_VAR" > ` + outputFile + `
sleep 2
exit 0
`
	if err := os.WriteFile(scriptPath, []byte(scriptContent), 0755); err != nil {
		t.Fatalf("Failed to create script: %v", err)
	}

	hookContent := `
[hook]
name=env-service
mode=test
trigger=start

[env]
SERVICE_VAR=test_value

[run.env]
SERVICE_VAR=runtime_value

[run]
service=` + scriptPath + `

[run.service]
success-codes=0
`

	hookFile := filepath.Join(tmpDir, "service.hook")
	if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
		t.Fatalf("Failed to create hook file: %v", err)
	}

	manager := NewManager(ExecutionMode("test"), tmpDir, tmpDir)

	executor, err := manager.ExecuteTrigger(Trigger("start"))
	if err != nil {
		t.Fatalf("Failed to execute trigger: %v", err)
	}

	// Check if hook was parsed correctly
	exec, _ := executor.GetExecution("env-service")
	hook := exec.Hook
	t.Logf("Persistent env count: %d", len(hook.PersistentEnv))
	for _, env := range hook.PersistentEnv {
		t.Logf("  Persistent: %s=%s", env.Key, env.Value)
	}
	t.Logf("Run env count: %d", len(hook.RunEnv))
	for _, env := range hook.RunEnv {
		t.Logf("  RunEnv: %s=%s", env.Key, env.Value)
	}

	// Wait for service to write file and exit
	time.Sleep(3 * time.Second)

	// Check that run-env var was used (not persistent env)
	content, err := os.ReadFile(outputFile)
	if err != nil {
		t.Fatalf("Failed to read output file: %v", err)
	}

	expected := "SERVICE_VAR=runtime_value\n"
	if string(content) != expected {
		t.Errorf("Expected '%s', got '%s'", expected, string(content))
	}

	// Verify persistent env var was set globally
	val, exists := proc.EnvironmentVariables.Get("SERVICE_VAR")
	if !exists || val != "test_value" {
		t.Error("Persistent env var should be set to test_value")
	}
}

// Helper function to check if a process is running
func isProcessRunning(pid int) bool {
	// Try to send signal 0 (null signal) which just checks if process exists
	err := syscall.Kill(pid, 0)
	return err == nil
}
