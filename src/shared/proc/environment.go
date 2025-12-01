package proc

import "os"

type Environments map[string]string

var EnvironmentVariables = Environments{}

func (e *Environments) Set(key, value string) {
	(*e)[key] = value
}

func (e *Environments) Get(key string) (string, bool) {
	value, exists := (*e)[key]
	return value, exists
}

func (e *Environments) Delete(key string) {
	delete(*e, key)
}

func (e *Environments) ToSlice() []string {
	var envSlice []string
	for key, value := range *e {
		envSlice = append(envSlice, key+"="+value)
	}
	return envSlice
}

// initEnvironment initializes the EnvironmentVariables map with the current
// process's environment variables.
func initEnvironment() {
	for _, env := range os.Environ() {
		// Split environment variable into key and value
		for i := 0; i < len(env); i++ {
			if env[i] == '=' {
				key := env[:i]
				value := env[i+1:]
				EnvironmentVariables[key] = value
				break
			}
		}
	}
}
