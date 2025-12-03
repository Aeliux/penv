package hook

import (
	"fmt"
	"sort"
)

// DependencyGraph represents the dependency relationships between hooks
type DependencyGraph struct {
	hooks map[string]*Hook
	edges map[string][]string // hookName -> list of dependencies
}

// NewDependencyGraph creates a new dependency graph
func NewDependencyGraph() *DependencyGraph {
	return &DependencyGraph{
		hooks: make(map[string]*Hook),
		edges: make(map[string][]string),
	}
}

// AddHook adds a hook to the dependency graph
func (g *DependencyGraph) AddHook(hook *Hook) error {
	if _, exists := g.hooks[hook.Name]; exists {
		return fmt.Errorf("duplicate hook name: %s", hook.Name)
	}

	g.hooks[hook.Name] = hook
	g.edges[hook.Name] = hook.Requires
	return nil
}

// Validate checks for missing dependencies and circular dependencies
func (g *DependencyGraph) Validate() error {
	// Check for missing dependencies
	for hookName, deps := range g.edges {
		for _, dep := range deps {
			if _, exists := g.hooks[dep]; !exists {
				return fmt.Errorf("hook '%s' requires missing dependency: %s", hookName, dep)
			}
		}
	}

	// Check for circular dependencies
	if err := g.detectCycles(); err != nil {
		return err
	}

	return nil
}

// detectCycles uses DFS to detect circular dependencies
func (g *DependencyGraph) detectCycles() error {
	visited := make(map[string]bool)
	recStack := make(map[string]bool)

	for hookName := range g.hooks {
		if !visited[hookName] {
			if err := g.dfsDetectCycle(hookName, visited, recStack, []string{}); err != nil {
				return err
			}
		}
	}

	return nil
}

// dfsDetectCycle performs DFS to detect cycles
func (g *DependencyGraph) dfsDetectCycle(current string, visited, recStack map[string]bool, path []string) error {
	visited[current] = true
	recStack[current] = true
	path = append(path, current)

	for _, dep := range g.edges[current] {
		if !visited[dep] {
			if err := g.dfsDetectCycle(dep, visited, recStack, path); err != nil {
				return err
			}
		} else if recStack[dep] {
			// Found a cycle
			cyclePath := append(path, dep)
			return fmt.Errorf("circular dependency detected: %v", cyclePath)
		}
	}

	recStack[current] = false
	return nil
}

// TopologicalSort returns hooks in execution order (dependencies first)
// Returns a list of batches where hooks in each batch can run in parallel
func (g *DependencyGraph) TopologicalSort() ([][]string, error) {
	if err := g.Validate(); err != nil {
		return nil, err
	}

	// Calculate in-degree for each hook (number of dependencies)
	inDegree := make(map[string]int)
	for hookName := range g.hooks {
		inDegree[hookName] = len(g.edges[hookName])
	}

	// Find all hooks with no dependencies (in-degree 0)
	var batches [][]string
	processed := make(map[string]bool)

	for len(processed) < len(g.hooks) {
		var batch []string

		// Find all hooks with in-degree 0 that haven't been processed
		for hookName := range g.hooks {
			if !processed[hookName] && inDegree[hookName] == 0 {
				batch = append(batch, hookName)
			}
		}

		if len(batch) == 0 {
			// This shouldn't happen if Validate passed, but just in case
			return nil, fmt.Errorf("unable to resolve dependencies (possible cycle)")
		}

		// Sort batch for deterministic execution
		sort.Strings(batch)
		batches = append(batches, batch)

		// Mark batch as processed and update in-degrees
		for _, hookName := range batch {
			processed[hookName] = true

			// Decrease in-degree for all hooks that have this hook as a dependency
			for dependent := range g.hooks {
				for _, dep := range g.edges[dependent] {
					if dep == hookName {
						inDegree[dependent]--
					}
				}
			}
		}
	}

	return batches, nil
}

// GetHook retrieves a hook by name
func (g *DependencyGraph) GetHook(name string) (*Hook, bool) {
	hook, exists := g.hooks[name]
	return hook, exists
}

// GetAllHooks returns all hooks in the graph
func (g *DependencyGraph) GetAllHooks() []*Hook {
	hooks := make([]*Hook, 0, len(g.hooks))
	for _, hook := range g.hooks {
		hooks = append(hooks, hook)
	}
	return hooks
}

// FilterByMode returns only hooks that support the given mode
func (g *DependencyGraph) FilterByMode(mode ExecutionMode) *DependencyGraph {
	filtered := NewDependencyGraph()
	modeStr := string(mode)

	for name, hook := range g.hooks {
		// If no modes specified, hook runs in all modes
		if len(hook.Modes) == 0 {
			filtered.hooks[name] = hook
			continue
		}

		// Check if hook supports this mode
		for _, m := range hook.Modes {
			if m == modeStr {
				filtered.hooks[name] = hook
				break
			}
		}
	}

	// Filter edges to only include hooks that are in the filtered set
	for name := range filtered.hooks {
		var validDeps []string
		for _, dep := range g.edges[name] {
			if _, exists := filtered.hooks[dep]; exists {
				validDeps = append(validDeps, dep)
			}
		}
		filtered.edges[name] = validDeps
	}

	return filtered
}

// FilterByTrigger returns only hooks that support the given trigger
func (g *DependencyGraph) FilterByTrigger(trigger Trigger) *DependencyGraph {
	filtered := NewDependencyGraph()
	triggerStr := string(trigger)

	for name, hook := range g.hooks {
		// If no triggers specified, hook responds to all triggers
		if len(hook.Triggers) == 0 {
			filtered.hooks[name] = hook
			continue
		}

		// Check if hook supports this trigger
		for _, t := range hook.Triggers {
			if t == triggerStr {
				filtered.hooks[name] = hook
				break
			}
		}
	}

	// Filter edges to only include hooks that are in the filtered set
	for name := range filtered.hooks {
		var validDeps []string
		for _, dep := range g.edges[name] {
			if _, exists := filtered.hooks[dep]; exists {
				validDeps = append(validDeps, dep)
			}
		}
		filtered.edges[name] = validDeps
	}

	return filtered
}
