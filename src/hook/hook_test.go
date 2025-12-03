package hook

import (
	"os"
	"path/filepath"
	"testing"

	"penv/shared/logger"
	"penv/shared/proc"

	"go.uber.org/zap/zapcore"
)

func TestParser(t *testing.T) {
	tmpDir := t.TempDir()

	hookContent := `[hook]
name=test-parser
description=Test hook for parser
modes=test,dev
triggers=start
requires=dep1,dep2
priority=50

[env]
PERSIST_VAR=persistent_value
APP_PATH=$HOME/app

[run]
command=echo test

[run.env]
RUN_VAR=run_value
TEMP_PATH=/tmp/test

[run.options]
workdir=/tmp
`

	hookFile := filepath.Join(tmpDir, "test.hook")
	if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
		t.Fatalf("Failed to create hook file: %v", err)
	}

	parser := NewParser(ExecutionMode("test"))
	h, err := parser.ParseFile(hookFile)
	if err != nil {
		t.Fatalf("Failed to parse hook: %v", err)
	}

	// Test metadata
	if h.Name != "test-parser" {
		t.Errorf("Expected name 'test-parser', got '%s'", h.Name)
	}

	// Test persistent env
	if len(h.PersistentEnv) != 2 {
		t.Errorf("Expected 2 persistent env vars, got %d", len(h.PersistentEnv))
	}

	for _, envVar := range h.PersistentEnv {
		if envVar.Key == "PERSIST_VAR" && envVar.Value != "persistent_value" {
			t.Errorf("Expected PERSIST_VAR='persistent_value', got '%s'", envVar.Value)
		}
		if envVar.Key == "APP_PATH" && envVar.Value != "$HOME/app" {
			t.Errorf("Expected APP_PATH='$HOME/app', got '%s'", envVar.Value)
		}
	}

	// Test run env
	if len(h.RunEnv) != 2 {
		t.Errorf("Expected 2 run env vars, got %d", len(h.RunEnv))
	}

	for _, envVar := range h.RunEnv {
		if envVar.Key == "RUN_VAR" && envVar.Value != "run_value" {
			t.Errorf("Expected RUN_VAR='run_value', got '%s'", envVar.Value)
		}
		if envVar.Key == "TEMP_PATH" && envVar.Value != "/tmp/test" {
			t.Errorf("Expected TEMP_PATH='/tmp/test', got '%s'", envVar.Value)
		}
	}

	// Test command
	if h.RunType != RunTypeCommand {
		t.Errorf("Expected RunType 'command', got '%s'", h.RunType)
	}
	if h.Command != "echo test" {
		t.Errorf("Expected command 'echo test', got '%s'", h.Command)
	}

	// Test workdir
	if h.WorkDir != "/tmp" {
		t.Errorf("Expected workdir '/tmp', got '%s'", h.WorkDir)
	}
}

func TestEnvOnlyHook(t *testing.T) {
	tmpDir := t.TempDir()

	hookContent := `[hook]
name=env-only
modes=test
triggers=start

[env]
GLOBAL_VAR=global_value
`

	hookFile := filepath.Join(tmpDir, "env-only.hook")
	if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
		t.Fatalf("Failed to create hook file: %v", err)
	}

	parser := NewParser(ExecutionMode("test"))
	h, err := parser.ParseFile(hookFile)
	if err != nil {
		t.Fatalf("Failed to parse hook: %v", err)
	}

	if h.RunType != "" {
		t.Errorf("Env-only hook should have empty RunType, got '%s'", h.RunType)
	}
	if len(h.PersistentEnv) != 1 {
		t.Errorf("Expected 1 persistent env var, got %d", len(h.PersistentEnv))
	}
}

func TestShellHookExecution(t *testing.T) {
	tmpDir := t.TempDir()

	hookContent := `[hook]
name=shell-hook
modes=test
triggers=start

[run]
shell="""#!/bin/bash
exit 49"""
`

	hookFile := filepath.Join(tmpDir, "shell-hook.hook")
	if err := os.WriteFile(hookFile, []byte(hookContent), 0644); err != nil {
		t.Fatalf("Failed to create hook file: %v", err)
	}

	manager := NewManager(ExecutionMode("test"), tmpDir, tmpDir)

	executor, err := manager.ExecuteTrigger(Trigger("start"))
	if err == nil {
		t.Fatal("Expected error from shell hook execution, got nil")
	}
	if executor == nil {
		t.Fatal("Expected executor to be returned even on error")
	}

	exec, exists := executor.GetExecution("shell-hook")
	if !exists {
		t.Fatal("Shell hook execution not tracked")
	}
	if exec.Status != StatusFailed {
		t.Errorf("Expected status failed, got %s", exec.Status)
	}
	if exec.ExitCode != 49 {
		t.Errorf("Expected exit code 49, got %d", exec.ExitCode)
	}
}

func TestDependencyGraph(t *testing.T) {
	graph := NewDependencyGraph()

	hooks := []*Hook{
		{Name: "a", Requires: []string{}},
		{Name: "b", Requires: []string{"a"}},
		{Name: "c", Requires: []string{"a"}},
		{Name: "d", Requires: []string{"b", "c"}},
	}

	for _, h := range hooks {
		graph.AddHook(h)
	}

	batches, err := graph.TopologicalSort()
	if err != nil {
		t.Fatalf("Topological sort failed: %v", err)
	}

	if len(batches) != 3 {
		t.Errorf("Expected 3 batches, got %d", len(batches))
	}
}

func TestCircularDependency(t *testing.T) {
	graph := NewDependencyGraph()

	hooks := []*Hook{
		{Name: "a", Requires: []string{"b"}},
		{Name: "b", Requires: []string{"c"}},
		{Name: "c", Requires: []string{"a"}},
	}

	for _, h := range hooks {
		graph.AddHook(h)
	}

	_, err := graph.TopologicalSort()
	if err == nil {
		t.Error("Expected error for circular dependency")
	}
}

func TestModeFiltering(t *testing.T) {
	tmpDir := t.TempDir()

	// Create hooks with different modes
	devHook := `[hook]
name=dev-hook
modes=dev
triggers=start

[run]
command=echo dev
`

	prodHook := `[hook]
name=prod-hook
modes=prod
triggers=start

[run]
command=echo prod
`

	allModesHook := `[hook]
name=all-modes-hook
triggers=start

[run]
command=echo all
`

	os.WriteFile(filepath.Join(tmpDir, "dev.hook"), []byte(devHook), 0644)
	os.WriteFile(filepath.Join(tmpDir, "prod.hook"), []byte(prodHook), 0644)
	os.WriteFile(filepath.Join(tmpDir, "all.hook"), []byte(allModesHook), 0644)

	// Test with dev mode - should load dev-hook and all-modes-hook
	devManager := NewManager(ExecutionMode("dev"), tmpDir, tmpDir)
	devHooks := devManager.GetAllHooks()
	if len(devHooks) != 2 {
		t.Errorf("Dev mode: expected 2 hooks, got %d", len(devHooks))
	}

	// Test with prod mode - should load prod-hook and all-modes-hook
	prodManager := NewManager(ExecutionMode("prod"), tmpDir, tmpDir)
	prodHooks := prodManager.GetAllHooks()
	if len(prodHooks) != 2 {
		t.Errorf("Prod mode: expected 2 hooks, got %d", len(prodHooks))
	}

	// Verify correct hooks were loaded
	devHookNames := make(map[string]bool)
	for _, h := range devHooks {
		devHookNames[h.Name] = true
	}
	if !devHookNames["dev-hook"] || !devHookNames["all-modes-hook"] {
		t.Error("Dev mode should load dev-hook and all-modes-hook")
	}
	if devHookNames["prod-hook"] {
		t.Error("Dev mode should not load prod-hook")
	}
}

func init() {
	logger.InitSimple("/tmp/hook-test.log", zapcore.InfoLevel)
	proc.ResetEnvironments()
}
