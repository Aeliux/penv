package main

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"time"

	"penv/shared/proc"

	"github.com/urfave/cli/v3"
)

const appVersion = "3.0.0"

var runCmd = &cli.Command{
	Name:  "run",
	Usage: "Run an executable for test",
	// add executable positinal argument
	ArgsUsage: "<executable>",
	Flags: []cli.Flag{
		&cli.IntFlag{
			Name:  "timeout",
			Usage: "Timeout in seconds to wait before killing the process",
			Value: 10,
		},
	},
	Action: func(ctx context.Context, cmd *cli.Command) error {
		args := cmd.Args().Slice()
		if len(args) < 1 {
			return cli.Exit("No executable provided", 1)
		}
		executable := args[0]
		timeout := cmd.Int("timeout")

		eInst := proc.GetCmd(executable, args[1:], map[string]string{}, os.Stdin, os.Stdout, os.Stderr)
		go proc.StartProcess(eInst, func(cmd *exec.Cmd, err error) {
			if err != nil {
				fmt.Println("Error:", err)
			} else {
				fmt.Println("Process exited successfully")
			}
		})
		// Wait for a moment to ensure the process has started
		time.Sleep(500 * time.Millisecond)
		go func() {
			i := 0
			for {
				i++
				fmt.Println("Process running...")
				time.Sleep(1 * time.Second)
				if i == 3 {
					proc.RunningPids.KillProcess(eInst.Process.Pid, timeout)
					fmt.Println("Sent sighup signal to process")
				}
			}
		}()
		eInst.Wait()
		fmt.Println("Process finished")
		return nil
	},
}

var rootCmd = &cli.Command{
	Name:    "penv",
	Usage:   "Run disposable linux environments",
	Version: appVersion,
	Commands: []*cli.Command{
		runCmd,
	},
}

func main() {
	rootCmd.Run(context.Background(), os.Args)
}
