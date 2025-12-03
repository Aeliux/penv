package hook

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"

	"penv/shared/proc"
)

func TestPersistentEnvUpdates(t *testing.T) {
	tmpDir := t.TempDir()

	// Reset environment
	proc.ResetEnvironments()
	initialCount := proc.EnvironmentVariables.Len()

	// Create hook with persistent env
	hookContent := `[hook]
name=env-setter
modes=test
triggers=start

[env]
TEST_PERSISTENT=persistent_value
TEST_PATH=/opt/test
`

	hookFile := filepath.Join(tmpDir, "env-setter.hook")
	os.WriteFile(hookFile, []byte(hookContent), 0644)

	manager := NewManager(ExecutionMode("test"), tmpDir)
	manager.LoadHooksFromDirectory(tmpDir)

	if err := manager.ExecuteTrigger(Trigger("start")); err != nil {
		t.Fatalf("Failed to execute trigger: %v", err)
	}

	// Check that persistent env vars were added to proc.EnvironmentVariables
	val, exists := proc.EnvironmentVariables.Get("TEST_PERSISTENT")
	if !exists {
		t.Error("TEST_PERSISTENT not found in proc.EnvironmentVariables")
	}
	if val != "persistent_value" {
		t.Errorf("Expected TEST_PERSISTENT='persistent_value', got '%s'", val)
	}

	val, exists = proc.EnvironmentVariables.Get("TEST_PATH")
	if !exists {
		t.Error("TEST_PATH not found in proc.EnvironmentVariables")
	}
	if val != "/opt/test" {
		t.Errorf("Expected TEST_PATH='/opt/test', got '%s'", val)
	}

	// Verify count increased
	if proc.EnvironmentVariables.Len() <= initialCount {
		t.Error("proc.EnvironmentVariables count should have increased")
	}
}

func TestVariableExpansion(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	// Set a base variable
	proc.EnvironmentVariables.Set("BASE_DIR", "/opt/app")

	hookContent := `[hook]
name=var-expander
modes=test
triggers=start

[env]
APP_BIN=${BASE_DIR}/bin
APP_CONFIG=${BASE_DIR}/config
APP_FULL=${APP_BIN}s/executable

[run]
shell="#!/bin/bash
echo $EXP3 > expanded.txt"

[run.options]
workdir=` + tmpDir + `

[run.env]
EXP=${APP_FULL}
EXP2=${EXP}a
EXP3=${EXP2}b
`

	hookFile := filepath.Join(tmpDir, "expander.hook")
	os.WriteFile(hookFile, []byte(hookContent), 0644)

	manager := NewManager(ExecutionMode("test"), tmpDir)
	manager.LoadHooksFromDirectory(tmpDir)
	manager.ExecuteTrigger(Trigger("start"))

	// Check expanded values
	val, _ := proc.EnvironmentVariables.Get("APP_BIN")
	if val != "/opt/app/bin" {
		t.Errorf("Expected APP_BIN='/opt/app/bin', got '%s'", val)
	}

	val, _ = proc.EnvironmentVariables.Get("APP_CONFIG")
	if val != "/opt/app/config" {
		t.Errorf("Expected APP_CONFIG='/opt/app/config', got '%s'", val)
	}

	val, _ = proc.EnvironmentVariables.Get("APP_FULL")
	if val != "/opt/app/bins/executable" {
		t.Errorf("Expected APP_FULL='/opt/app/bins/executable', got '%s'", val)
	}

	// Check that the script saw the fully expanded variable
	expandedFile := filepath.Join(tmpDir, "expanded.txt")
	data, err := os.ReadFile(expandedFile)
	if err != nil {
		t.Fatalf("Failed to read expanded.txt: %v", err)
	}
	content := strings.TrimSpace(string(data))
	expected := "/opt/app/bins/executableab"
	if content != expected {
		t.Errorf("Expected expanded content '%s', got '%s'", expected, content)
	}
}

func TestRunEnvDoesNotAffectGlobal(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	outputFile := filepath.Join(tmpDir, "output.txt")

	// Create script that outputs RUN_ONLY var
	scriptPath := filepath.Join(tmpDir, "test.sh")
	scriptContent := "#!/bin/sh\necho \"RUN_ONLY=$RUN_ONLY\" > output.txt\n"
	os.WriteFile(scriptPath, []byte(scriptContent), 0755)

	hookContent := `[hook]
name=run-env-test
modes=test
triggers=start

[run]
command=./test.sh

[run.env]
RUN_ONLY=should_not_be_global

[run.options]
workdir=` + tmpDir + `
`

	hookFile := filepath.Join(tmpDir, "test.hook")
	os.WriteFile(hookFile, []byte(hookContent), 0644)

	manager := NewManager(ExecutionMode("test"), tmpDir)
	manager.LoadHooksFromDirectory(tmpDir)
	manager.ExecuteTrigger(Trigger("start"))

	// Verify the script saw the variable
	data, _ := os.ReadFile(outputFile)
	if !strings.Contains(string(data), "RUN_ONLY=should_not_be_global") {
		t.Errorf("Script didn't see RUN_ONLY variable: %s", string(data))
	}

	// Verify it's NOT in proc.EnvironmentVariables
	if _, exists := proc.EnvironmentVariables.Get("RUN_ONLY"); exists {
		t.Error("RUN_ONLY should not be in proc.EnvironmentVariables")
	}
}

func TestEnvOnlyHookExecution(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	hookContent := `[hook]
name=env-only-hook
modes=test
triggers=start

[env]
ENV_ONLY_VAR=env_only_value
`

	hookFile := filepath.Join(tmpDir, "env-only.hook")
	os.WriteFile(hookFile, []byte(hookContent), 0644)

	manager := NewManager(ExecutionMode("test"), tmpDir)
	manager.LoadHooksFromDirectory(tmpDir)

	if err := manager.ExecuteTrigger(Trigger("start")); err != nil {
		t.Fatalf("Env-only hook should not error: %v", err)
	}

	// Check execution status
	exec, exists := manager.GetHookExecution("env-only-hook")
	if !exists {
		t.Fatal("Env-only hook execution not tracked")
	}
	if exec.Status != StatusCompleted {
		t.Errorf("Expected status completed, got %s", exec.Status)
	}

	// Check env var was set
	val, exists := proc.EnvironmentVariables.Get("ENV_ONLY_VAR")
	if !exists {
		t.Error("ENV_ONLY_VAR not set by env-only hook")
	}
	if val != "env_only_value" {
		t.Errorf("Expected ENV_ONLY_VAR='env_only_value', got '%s'", val)
	}
}

func TestEnvPropagationAcrossHooks(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	outputFile := filepath.Join(tmpDir, "output.txt")

	// Create script for second hook
	scriptPath := filepath.Join(tmpDir, "check.sh")
	scriptContent := "#!/bin/sh\necho \"SHARED=$SHARED\" > output.txt\n"
	os.WriteFile(scriptPath, []byte(scriptContent), 0755)

	// First hook: sets env
	hook1Content := `[hook]
name=set-shared
modes=test
triggers=start
priority=100

[env]
SHARED=shared_value
`

	// Second hook: uses env from first hook
	hook2Content := `[hook]
name=use-shared
requires=set-shared
modes=test
triggers=start

[run]
command=./check.sh

[run.options]
workdir=` + tmpDir + `
`

	os.WriteFile(filepath.Join(tmpDir, "set.hook"), []byte(hook1Content), 0644)
	os.WriteFile(filepath.Join(tmpDir, "use.hook"), []byte(hook2Content), 0644)

	manager := NewManager(ExecutionMode("test"), tmpDir)
	manager.LoadHooksFromDirectory(tmpDir)
	manager.ExecuteTrigger(Trigger("start"))

	// Wait a bit for execution
	time.Sleep(50 * time.Millisecond)

	// Check that second hook saw the variable
	data, err := os.ReadFile(outputFile)
	if err != nil {
		t.Fatalf("Failed to read output: %v", err)
	}
	if !strings.Contains(string(data), "SHARED=shared_value") {
		t.Errorf("Second hook didn't see SHARED variable: %s", string(data))
	}
}

func TestDependencyFailureWithEnvHook(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	// First hook: env-only, should succeed
	hook1 := `[hook]
name=base-env
modes=test
triggers=start

[env]
BASE=value
`

	// Second hook: fails
	hook2 := `[hook]
name=failing
requires=base-env
modes=test
triggers=start

[run]
command=false
`

	// Third hook: depends on failing hook
	hook3 := `[hook]
name=dependent
requires=failing
modes=test
triggers=start

[run]
command=echo test
`

	os.WriteFile(filepath.Join(tmpDir, "base.hook"), []byte(hook1), 0644)
	os.WriteFile(filepath.Join(tmpDir, "fail.hook"), []byte(hook2), 0644)
	os.WriteFile(filepath.Join(tmpDir, "dep.hook"), []byte(hook3), 0644)

	manager := NewManager(ExecutionMode("test"), tmpDir)
	manager.LoadHooksFromDirectory(tmpDir)

	err := manager.ExecuteTrigger(Trigger("start"))
	if err == nil {
		t.Error("Expected error due to failing hook")
	}

	// Base env hook should complete
	exec, exists := manager.GetHookExecution("base-env")
	if !exists {
		t.Fatal("base-env execution not found")
	}
	if exec.Status != StatusCompleted {
		t.Errorf("Expected base-env to complete, got %s", exec.Status)
	}

	// Failing hook should fail
	exec, exists = manager.GetHookExecution("failing")
	if !exists {
		t.Fatal("failing execution not found")
	}
	if exec.Status != StatusFailed {
		t.Errorf("Expected failing to fail, got %s", exec.Status)
	}

	// Dependent hook should be skipped
	_, exists = manager.GetHookExecution("dependent")
	if !exists {
		t.Fatal("dependent execution not found")
	}
	exec, _ = manager.GetHookExecution("dependent")
	if exec.Status != StatusSkipped {
		t.Errorf("Expected dependent to be skipped, got %s", exec.Status)
	}

	// But base env should have set its variable
	val, exists := proc.EnvironmentVariables.Get("BASE")
	if !exists || val != "value" {
		t.Error("BASE env var should be set despite later failures")
	}
}

func TestPinitEnvVars(t *testing.T) {
	tmpDir := t.TempDir()
	proc.ResetEnvironments()

	outputFile := filepath.Join(tmpDir, "pinit-vars.txt")
	scriptPath := filepath.Join(tmpDir, "capture.sh")
	scriptContent := `#!/bin/sh
echo "PINIT_HOOK=$PINIT_HOOK" > pinit-vars.txt
echo "PINIT_HOOK_MODE=$PINIT_HOOK_MODE" >> pinit-vars.txt
echo "PINIT_HOOK_TRIGGER=$PINIT_HOOK_TRIGGER" >> pinit-vars.txt
`
	os.WriteFile(scriptPath, []byte(scriptContent), 0755)

	hookContent := `[hook]
name=pinit-test
modes=test-mode
triggers=test-trigger

[run]
command=./capture.sh

[run.options]
workdir=` + tmpDir + `
`

	os.WriteFile(filepath.Join(tmpDir, "test.hook"), []byte(hookContent), 0644)

	manager := NewManager(ExecutionMode("test-mode"), tmpDir)
	manager.LoadHooksFromDirectory(tmpDir)
	manager.ExecuteTrigger(Trigger("test-trigger"))

	time.Sleep(50 * time.Millisecond)

	data, _ := os.ReadFile(outputFile)
	content := string(data)

	if !strings.Contains(content, "PINIT_HOOK=pinit-test") {
		t.Errorf("PINIT_HOOK not set correctly: %s", content)
	}
	if !strings.Contains(content, "PINIT_HOOK_MODE=test-mode") {
		t.Errorf("PINIT_HOOK_MODE not set correctly: %s", content)
	}
	if !strings.Contains(content, "PINIT_HOOK_TRIGGER=test-trigger") {
		t.Errorf("PINIT_HOOK_TRIGGER not set correctly: %s", content)
	}
}
