package hook

import (
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"

	"github.com/hashicorp/go-version"
	"gopkg.in/ini.v1"
)

// Parser handles parsing of hook configuration files
type Parser struct {
	mode ExecutionMode
}

// NewParser creates a new hook parser that filters hooks by mode
func NewParser(mode ExecutionMode) *Parser {
	return &Parser{
		mode: mode,
	}
}

// ParseFile parses a hook file and returns a Hook object
func (p *Parser) ParseFile(filePath string) (*Hook, error) {
	// Load with ini.v1 - it handles backtick multiline strings natively
	cfg, err := ini.Load(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to load hook file: %w", err)
	}

	hook := &Hook{
		FilePath:      filePath,
		PersistentEnv: []EnvVariable{},
		RunEnv:        []EnvVariable{},
		SuccessCodes:  []int{0},
	}

	// Parse [hook] hookSection
	// Required
	hookSection, err := cfg.GetSection("hook")
	if err != nil {
		return nil, fmt.Errorf("missing [hook] section in %s", filePath)
	}

	if key, err := hookSection.GetKey("name"); err == nil {
		hook.Name = key.String()
	}
	if key, err := hookSection.GetKey("description"); err == nil {
		hook.Description = key.String()
	}
	if key, err := hookSection.GetKey("version"); err == nil {
		hookVer, err := version.NewVersion(key.String())
		if err == nil {
			hook.Version = hookVer
		}
	}
	if key, err := hookSection.GetKey("author"); err == nil {
		hook.Author = key.String()
	}
	if key, err := hookSection.GetKey("success-codes"); err == nil {
		value := key.String()
		if value != "" {
			codesStr := splitAndTrim(value, ",")
			hook.SuccessCodes = []int{}
			for _, codeStr := range codesStr {
				code, err := strconv.Atoi(codeStr)
				if err != nil {
					return nil, fmt.Errorf("invalid success code '%s' in %s: %w", codeStr, filePath, err)
				}
				hook.SuccessCodes = append(hook.SuccessCodes, code)
			}
		}
	}
	if key, err := hookSection.GetKey("single-run"); err == nil {
		hook.SingleRun = key.MustBool(false)
	}

	// Parse [requirements] section
	if reqSection, err := cfg.GetSection("requirements"); err == nil {
		if key, err := reqSection.GetKey("hooks"); err == nil {
			value := key.String()
			if value != "" {
				hook.RequiredHooks = splitAndTrim(value, ",")
			}
		}
		if key, err := reqSection.GetKey("pinit-version"); err == nil {
			constraintStr := key.String()
			if constraintStr != "" {
				constraints, err := version.NewConstraint(constraintStr)
				if err != nil {
					return nil, fmt.Errorf("invalid pinit-version constraint '%s': %w", constraintStr, err)
				}
				hook.PinitVersion = &constraints
			}
		}
		if key, err := reqSection.GetKey("penv-version"); err == nil {
			constraintStr := key.String()
			if constraintStr != "" {
				constraints, err := version.NewConstraint(constraintStr)
				if err != nil {
					return nil, fmt.Errorf("invalid penv-version constraint '%s': %w", constraintStr, err)
				}
				hook.PenvVersion = &constraints
			}
		}
	}

	// Parse [env:local] section
	if runEnvSection, err := cfg.GetSection("env:local"); err == nil {
		for _, key := range runEnvSection.Keys() {
			hook.RunEnv = append(hook.RunEnv, EnvVariable{
				Key:   key.Name(),
				Value: key.String(),
			})
		}
	}

	// Parse [conditions] section
	if condSection, err := cfg.GetSection("conditions"); err == nil {
		if key, err := condSection.GetKey("script"); err == nil {
			hook.ConditionScript = key.String()
		}
		if key, err := condSection.GetKey("modes"); err == nil {
			value := key.String()
			if value != "" {
				hook.Modes = splitAndTrim(value, ",")
			}
		}
		if key, err := condSection.GetKey("triggers"); err == nil {
			value := key.String()
			if value != "" {
				hook.Triggers = splitAndTrim(value, ",")
			}
		}
	}

	// Parse [env:global] section
	if envSection, err := cfg.GetSection("env:global"); err == nil {
		for _, key := range envSection.Keys() {
			hook.PersistentEnv = append(hook.PersistentEnv, EnvVariable{
				Key:   key.Name(),
				Value: key.String(),
			})
		}
	}

	// Parse [run] section
	if runSection, err := cfg.GetSection("run"); err == nil {
		hook.ExecFormat = ExecFormatUndefined
		if key, err := runSection.GetKey("exec"); err == nil {
			hook.Exec = key.String()
			hook.RunType = RunTypeNormal
			// Determine ExecFormat based on exec content
			if strings.HasPrefix(hook.Exec, "#!") {
				hook.ExecFormat = ExecFormatScript
			} else {
				hook.ExecFormat = ExecFormatCommand
			}
		}
		if key, err := runSection.GetKey("type"); err == nil {
			runTypeStr := key.String()
			switch runTypeStr {
			case "normal":
				hook.RunType = RunTypeNormal
			case "service":
				hook.RunType = RunTypeService
			}
		}
		if key, err := runSection.GetKey("working-dir"); err == nil {
			hook.WorkDir = key.String()
		}

		// RunType specific fields
		hook.RestartCount = 0
		hook.TimeoutSeconds = 0

		if hook.RunType == RunTypeService {
			hook.SingleRun = true // Services are always single-run
			if key, err := runSection.GetKey("restart-count"); err == nil {
				value := key.String()
				if value != "" {
					count, err := strconv.Atoi(value)
					if err != nil {
						return nil, fmt.Errorf("invalid restart-count '%s' in %s: %w", value, filePath, err)
					}
					hook.RestartCount = count
				}
			}
		} else if hook.RunType == RunTypeNormal {
			if key, err := runSection.GetKey("timeout"); err == nil {
				value := key.String()
				if value != "" {
					timeout, err := strconv.Atoi(value)
					if err != nil {
						return nil, fmt.Errorf("invalid timeout '%s' in %s: %w", value, filePath, err)
					}
					hook.TimeoutSeconds = timeout
				}
			}
		}
	}

	// Validate hook
	if err := p.validate(hook); err != nil {
		return nil, fmt.Errorf("validation failed for %s: %w", filePath, err)
	}

	// Filter by mode - skip hooks that don't match
	if !p.matchesMode(hook) {
		return nil, nil // Return nil to indicate hook should be skipped
	}

	return hook, nil
}

// matchesMode checks if a hook should run in the current mode
func (p *Parser) matchesMode(hook *Hook) bool {
	// If no modes specified, hook runs in all modes
	if len(hook.Modes) == 0 {
		return true
	}

	// Check if hook supports this mode
	modeStr := string(p.mode)
	return slices.Contains(hook.Modes, modeStr)
}

// validate ensures the hook has required fields
func (p *Parser) validate(hook *Hook) error {
	if hook.Name == "" {
		return fmt.Errorf("hook name is required")
	}

	// Hook can be env-only (no run section) OR have one execution type
	hasRun := hook.Exec != ""
	hasEnv := len(hook.PersistentEnv) > 0

	// If has no env and no run, that's invalid
	if !hasRun && !hasEnv {
		return fmt.Errorf("hook did not specify any execution or environment variables updates")
	}

	return nil
}

// ParseDirectory parses all hook files in a directory
func (p *Parser) ParseDirectory(dirPath string) ([]*Hook, error) {
	var hooks []*Hook

	entries, err := os.ReadDir(dirPath)
	if err != nil {
		return nil, fmt.Errorf("failed to read directory: %w", err)
	}

	for _, entry := range entries {
		if entry.IsDir() {
			continue
		}

		// Parse files with .hook extension
		if strings.HasSuffix(entry.Name(), ".hook") {
			filePath := filepath.Join(dirPath, entry.Name())
			hook, err := p.ParseFile(filePath)
			if err != nil {
				return nil, err
			}
			// Skip hooks that don't match the mode
			if hook != nil {
				hooks = append(hooks, hook)
			}
		}
	}

	return hooks, nil
}

// splitAndTrim splits a string by delimiter and trims whitespace
func splitAndTrim(s, sep string) []string {
	parts := strings.Split(s, sep)
	result := make([]string, 0, len(parts))
	for _, part := range parts {
		if trimmed := strings.TrimSpace(part); trimmed != "" {
			result = append(result, trimmed)
		}
	}
	return result
}
