package console

import (
	"fmt"
	"os"

	"github.com/pterm/pterm"
)

// PtermPrinter implements ConsolePrinter using pterm.
type PtermPrinter struct {
	info    *pterm.PrefixPrinter
	warn    *pterm.PrefixPrinter
	error   *pterm.PrefixPrinter
	success *pterm.PrefixPrinter
}

// NewPtermPrinter creates a new pterm-based console printer.
func NewPtermPrinter() *PtermPrinter {
	return &PtermPrinter{
		info: &pterm.PrefixPrinter{
			Prefix: pterm.Prefix{
				Text:  "[i]",
				Style: pterm.NewStyle(pterm.FgCyan),
			},
		},
		warn: &pterm.PrefixPrinter{
			Prefix: pterm.Prefix{
				Text:  "[!]",
				Style: pterm.NewStyle(pterm.FgYellow),
			},
			MessageStyle: pterm.NewStyle(pterm.FgYellow),
		},
		error: &pterm.PrefixPrinter{
			Prefix: pterm.Prefix{
				Text:  "[x]",
				Style: pterm.NewStyle(pterm.FgRed),
			},
			MessageStyle: pterm.NewStyle(pterm.FgRed),
			Writer:       os.Stderr,
		},
		success: &pterm.PrefixPrinter{
			Prefix: pterm.Prefix{
				Text:  "[✓]",
				Style: pterm.NewStyle(pterm.FgGreen),
			},
			MessageStyle: pterm.NewStyle(pterm.FgGreen),
		},
	}
}

// Info prints an informational message.
func (p *PtermPrinter) Info(format string, a ...any) {
	p.info.Printfln(format, a...)
}

// Warn prints a warning message.
func (p *PtermPrinter) Warn(format string, a ...any) {
	p.warn.Printfln(format, a...)
}

// Error prints an error message.
func (p *PtermPrinter) Error(format string, a ...any) {
	p.error.Printfln(format, a...)
}

// Success prints a success message.
func (p *PtermPrinter) Success(format string, a ...any) {
	p.success.Printfln(format, a...)
}

// Printf prints a plain message without styling.
func (p *PtermPrinter) Printf(format string, a ...any) {
	fmt.Printf(format, a...)
	fmt.Println()
}
