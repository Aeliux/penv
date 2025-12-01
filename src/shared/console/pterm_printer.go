package console

import (
	"fmt"

	"github.com/pterm/pterm"
)

// PtermPrinter implements ConsolePrinter using pterm.
type PtermPrinter struct{}

// NewPtermPrinter creates a new pterm-based console printer.
func NewPtermPrinter() *PtermPrinter {
	return &PtermPrinter{}
}

// Info prints an informational message.
func (p *PtermPrinter) Info(format string, a ...interface{}) {
	pterm.Info.Printfln(format, a...)
}

// Warn prints a warning message.
func (p *PtermPrinter) Warn(format string, a ...interface{}) {
	pterm.Warning.Printfln(format, a...)
}

// Error prints an error message.
func (p *PtermPrinter) Error(format string, a ...interface{}) {
	pterm.Error.Printfln(format, a...)
}

// Success prints a success message.
func (p *PtermPrinter) Success(format string, a ...interface{}) {
	pterm.Success.Printfln(format, a...)
}

// Printf prints a plain message without styling.
func (p *PtermPrinter) Printf(format string, a ...interface{}) {
	fmt.Printf(format, a...)
	fmt.Println()
}
