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

	// Parse [hook] section
	if err := p.parseHookSectionFromINI(hook, cfg); err != nil {
		return nil, fmt.Errorf("error parsing hook section in %s: %w", filePath, err)
	}

	// Parse [env] section
	if envSection, err := cfg.GetSection("env"); err == nil {
		for _, key := range envSection.Keys() {
			hook.PersistentEnv = append(hook.PersistentEnv, EnvVariable{
				Key:   key.Name(),
				Value: key.String(),
			})
		}
	}

	// Parse [run] section
	if err := p.parseRunSectionFromINI(hook, cfg); err != nil {
		return nil, fmt.Errorf("error parsing run section in %s: %w", filePath, err)
	}

	// Parse [run.options] section
	if err := p.parseRunOptionsSectionFromINI(hook, cfg); err != nil {
		return nil, fmt.Errorf("error parsing run.options section in %s: %w", filePath, err)
	}

	// Parse [run.env] section
	if runEnvSection, err := cfg.GetSection("run.env"); err == nil {
		for _, key := range runEnvSection.Keys() {
			hook.RunEnv = append(hook.RunEnv, EnvVariable{
				Key:   key.Name(),
				Value: key.String(),
			})
		}
	}

	// Parse [run.service] section
	if err := p.parseRunServiceSectionFromINI(hook, cfg); err != nil {
		return nil, fmt.Errorf("error parsing run.service section in %s: %w", filePath, err)
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

// parseHookSectionFromINI parses the [hook] metadata section
func (p *Parser) parseHookSectionFromINI(hook *Hook, cfg *ini.File) error {
	section, err := cfg.GetSection("hook")
	if err != nil {
		// Hook section is optional if only env is defined
		return nil
	}

	if key, err := section.GetKey("name"); err == nil {
		hook.Name = key.String()
	}
	if key, err := section.GetKey("description"); err == nil {
		hook.Description = key.String()
	}
	if key, err := section.GetKey("version"); err == nil {
		hook.Version = key.String()
	}
	if key, err := section.GetKey("author"); err == nil {
		hook.Author = key.String()
	}
	if key, err := section.GetKey("requires"); err == nil {
		value := key.String()
		if value != "" {
			hook.Requires = splitAndTrim(value, ",")
		}
	}
	if key, err := section.GetKey("requires-pinit"); err == nil {
		value := key.String()
		if value != "" {
			constraints := splitAndTrim(value, ",")
			for _, c := range constraints {
				v, err := version.NewVersion(parseVersionConstraint(c))
				if err != nil {
					return fmt.Errorf("invalid pinit version constraint '%s': %w", c, err)
				}
				hook.RequiresPinit = append(hook.RequiresPinit, v)
			}
		}
	}
	if key, err := section.GetKey("modes"); err == nil {
		value := key.String()
		if value != "" {
			hook.Modes = splitAndTrim(value, ",")
		}
	}
	if key, err := section.GetKey("triggers"); err == nil {
		value := key.String()
		if value != "" {
			hook.Triggers = splitAndTrim(value, ",")
		}
	}

	return nil
}

// parseRunSectionFromINI parses the [run] execution section
func (p *Parser) parseRunSectionFromINI(hook *Hook, cfg *ini.File) error {
	section, err := cfg.GetSection("run")
	if err != nil {
		// Run section is optional if only env is defined
		return nil
	}

	if key, err := section.GetKey("command"); err == nil {
		hook.RunType = RunTypeCommand
		hook.Command = key.String()
	}
	if key, err := section.GetKey("shell"); err == nil {
		hook.RunType = RunTypeShell
		hook.Shell = key.String()
	}
	if key, err := section.GetKey("service"); err == nil {
		hook.RunType = RunTypeService
		hook.Service = key.String()
	}

	return nil
}

// parseRunOptionsSectionFromINI parses the [run.options] section
func (p *Parser) parseRunOptionsSectionFromINI(hook *Hook, cfg *ini.File) error {
	section, err := cfg.GetSection("run.options")
	if err != nil {
		return nil
	}

	if key, err := section.GetKey("workdir"); err == nil {
		hook.WorkDir = key.String()
	}

	return nil
}

// parseRunServiceSectionFromINI parses the [run.service] section
func (p *Parser) parseRunServiceSectionFromINI(hook *Hook, cfg *ini.File) error {
	section, err := cfg.GetSection("run.service")
	if err != nil {
		return nil
	}

	if key, err := section.GetKey("restart"); err == nil {
		hook.Restart = strings.ToLower(key.String()) == "true"
	}
	if key, err := section.GetKey("success-codes"); err == nil {
		value := key.String()
		if value != "" {
			codes := splitAndTrim(value, ",")
			hook.SuccessCodes = []int{}
			for _, code := range codes {
				c, err := strconv.Atoi(code)
				if err != nil {
					return fmt.Errorf("invalid success code '%s': %w", code, err)
				}
				hook.SuccessCodes = append(hook.SuccessCodes, c)
			}
		}
	}

	return nil
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
	hasRun := hook.Command != "" || hook.Shell != "" || hook.Service != ""
	hasEnv := len(hook.PersistentEnv) > 0

	// If has no env and no run, that's invalid
	if !hasRun && !hasEnv {
		return fmt.Errorf("hook must specify either [env] section or one of: command, shell, service")
	}

	// Should only have one execution type if run section exists
	if hasRun {
		count := 0
		if hook.Command != "" {
			count++
		}
		if hook.Shell != "" {
			count++
		}
		if hook.Service != "" {
			count++
		}
		if count > 1 {
			return fmt.Errorf("hook can only have one of: command, shell, or service")
		}
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

// parseVersionConstraint extracts version number from constraints like ">=3", "<4"
func parseVersionConstraint(constraint string) string {
	// Remove comparison operators
	constraint = strings.TrimPrefix(constraint, ">=")
	constraint = strings.TrimPrefix(constraint, "<=")
	constraint = strings.TrimPrefix(constraint, ">")
	constraint = strings.TrimPrefix(constraint, "<")
	constraint = strings.TrimPrefix(constraint, "=")
	return strings.TrimSpace(constraint)
}
