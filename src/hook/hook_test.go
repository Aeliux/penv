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

	parser := NewParser()
	h, err := parser.ParseFile(hookFile)
	if err != nil {
		t.Fatalf("Failed to parse hook: %v", err)
	}

	// Test metadata
	if h.Name != "test-parser" {
		t.Errorf("Expected name 'test-parser', got '%s'", h.Name)
	}

	// Test persistent env
	if h.PersistentEnv["PERSIST_VAR"] != "persistent_value" {
		t.Errorf("Expected PERSIST_VAR='persistent_value', got '%s'", h.PersistentEnv["PERSIST_VAR"])
	}

	// Test run env
	if h.RunEnv["RUN_VAR"] != "run_value" {
		t.Errorf("Expected RUN_VAR='run_value', got '%s'", h.RunEnv["RUN_VAR"])
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

	parser := NewParser()
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

func init() {
	logger.InitSimple("/tmp/hook-test.log", zapcore.InfoLevel)
	proc.ResetEnvironments()
}
