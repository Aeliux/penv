package proc

import (
	"os"
	"os/exec"
)

type Spawner interface {
	CreateCmd(stdin *os.File, stdout *os.File, stderr *os.File, envVars map[string]string) (*exec.Cmd, error) // CreateCmd creates the command to be executed
	Start(stdin *os.File, stdout *os.File, stderr *os.File, envVars map[string]string) error                  // Start prepares and starts the process, then cleans up any resources
}
