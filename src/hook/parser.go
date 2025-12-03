package hook

import (
	"bufio"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/hashicorp/go-version"
)

// Parser handles parsing of hook configuration files
type Parser struct{}

// NewParser creates a new hook parser
func NewParser() *Parser {
	return &Parser{}
}

// ParseFile parses a hook file and returns a Hook object
func (p *Parser) ParseFile(filePath string) (*Hook, error) {
	file, err := os.Open(filePath)
	if err != nil {
		return nil, fmt.Errorf("failed to open hook file: %w", err)
	}
	defer file.Close()

	hook := &Hook{
		FilePath:      filePath,
		PersistentEnv: []EnvVariable{},
		RunEnv:        []EnvVariable{},
		SuccessCodes:  []int{0},
	}

	scanner := bufio.NewScanner(file)
	currentSection := ""
	shellLines := []string{}
	inShellScript := false

	for scanner.Scan() {
		line := strings.TrimSpace(scanner.Text())

		// Skip empty lines and comments
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}

		// Handle multi-line shell script
		if inShellScript {
			if strings.HasSuffix(line, `"`) {
				// End of shell script
				shellLines = append(shellLines, strings.TrimSuffix(line, `"`))
				hook.Shell = strings.Join(shellLines, "\n")
				inShellScript = false
				shellLines = []string{}
			} else {
				shellLines = append(shellLines, line)
			}
			continue
		}

		// Section headers
		if strings.HasPrefix(line, "[") && strings.HasSuffix(line, "]") {
			currentSection = strings.Trim(line, "[]")
			continue
		}

		// Parse key-value pairs
		parts := strings.SplitN(line, "=", 2)
		if len(parts) != 2 {
			continue
		}

		key := strings.TrimSpace(parts[0])
		value := strings.TrimSpace(parts[1])

		// Remove quotes if present
		if len(value) >= 2 && value[0] == '"' && value[len(value)-1] == '"' {
			value = value[1 : len(value)-1]
		}

		// Handle multi-line shell script start
		if currentSection == "run" && key == "shell" && strings.HasPrefix(value, `"`) && !strings.HasSuffix(value, `"`) {
			inShellScript = true
			shellLines = append(shellLines, strings.TrimPrefix(value, `"`))
		}

		if err := p.parseKeyValue(hook, currentSection, key, value); err != nil {
			return nil, fmt.Errorf("error parsing %s: %w", filePath, err)
		}
	}

	if err := scanner.Err(); err != nil {
		return nil, fmt.Errorf("error reading hook file: %w", err)
	}

	// Validate hook
	if err := p.validate(hook); err != nil {
		return nil, fmt.Errorf("validation failed for %s: %w", filePath, err)
	}

	return hook, nil
}

// parseKeyValue parses a key-value pair based on the current section
func (p *Parser) parseKeyValue(hook *Hook, section, key, value string) error {
	switch section {
	case "hook":
		return p.parseHookSection(hook, key, value)
	case "env":
		pair := EnvVariable{
			Key:   key,
			Value: value,
		}
		hook.PersistentEnv = append(hook.PersistentEnv, pair)
	case "run":
		return p.parseRunSection(hook, key, value)
	case "run.options":
		return p.parseRunOptionsSection(hook, key, value)
	case "run.env":
		pair := EnvVariable{
			Key:   key,
			Value: value,
		}
		hook.RunEnv = append(hook.RunEnv, pair)
	case "run.service":
		return p.parseRunServiceSection(hook, key, value)
	}
	return nil
}

// parseHookSection parses the [hook] metadata section
func (p *Parser) parseHookSection(hook *Hook, key, value string) error {
	switch key {
	case "name":
		hook.Name = value
	case "description":
		hook.Description = value
	case "version":
		hook.Version = value
	case "author":
		hook.Author = value
	case "requires":
		if value != "" {
			hook.Requires = splitAndTrim(value, ",")
		}
	case "requires-pinit":
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
	case "modes":
		if value != "" {
			hook.Modes = splitAndTrim(value, ",")
		}
	case "triggers":
		if value != "" {
			hook.Triggers = splitAndTrim(value, ",")
		}
	}
	return nil
}

// parseRunSection parses the [run] execution section
func (p *Parser) parseRunSection(hook *Hook, key, value string) error {
	switch key {
	case "command":
		hook.RunType = RunTypeCommand
		hook.Command = value
	case "shell":
		hook.RunType = RunTypeShell
		hook.Shell = value
	case "service":
		hook.RunType = RunTypeService
		hook.Service = value
	}
	return nil
}

// parseRunOptionsSection parses the [run.options] section
func (p *Parser) parseRunOptionsSection(hook *Hook, key, value string) error {
	switch key {
	case "workdir":
		hook.WorkDir = value
	}
	return nil
}

// parseRunServiceSection parses the [run.service] section
func (p *Parser) parseRunServiceSection(hook *Hook, key, value string) error {
	switch key {
	case "restart":
		hook.Restart = strings.ToLower(value) == "true"
	case "success-codes":
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
			hooks = append(hooks, hook)
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
