package hook

import (
	"os"
	"strings"

	"penv/shared/proc"
)

// expandEnvVars performs basic variable expansion on a value
// Supports $VAR and ${VAR} syntax
// Checks: 1) envMap, 2) proc.EnvironmentVariables, 3) os.Getenv
func expandEnvVars(value string, envMap map[string]string) string {
	if !strings.Contains(value, "$") {
		return value // Fast path
	}

	var result strings.Builder
	result.Grow(len(value))

	i := 0
	for i < len(value) {
		if value[i] == '$' {
			if i+1 < len(value) && value[i+1] == '{' {
				// ${VAR} format
				end := strings.IndexByte(value[i+2:], '}')
				if end != -1 {
					varName := value[i+2 : i+2+end]
					if envMap != nil {
						if val, ok := envMap[varName]; ok {
							result.WriteString(val)
							i = i + 2 + end + 1
							continue
						}
					}
					if val, ok := proc.EnvironmentVariables.Get(varName); ok {
						result.WriteString(val)
					} else if val, ok := os.LookupEnv(varName); ok {
						result.WriteString(val)
					}
					i = i + 2 + end + 1
					continue
				}
			} else if i+1 < len(value) {
				// $VAR format
				start := i + 1
				end := start
				for end < len(value) && (isAlphaNum(value[end]) || value[end] == '_') {
					end++
				}
				if end > start {
					varName := value[start:end]
					if envMap != nil {
						if val, ok := envMap[varName]; ok {
							result.WriteString(val)
							i = end
							continue
						}
					}
					if val, ok := proc.EnvironmentVariables.Get(varName); ok {
						result.WriteString(val)
					} else if val, ok := os.LookupEnv(varName); ok {
						result.WriteString(val)
					}
					i = end
					continue
				}
			}
		}
		result.WriteByte(value[i])
		i++
	}

	return result.String()
}

func isAlphaNum(c byte) bool {
	return (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9')
}
