package console

import (
	"fmt"

	"github.com/pterm/pterm"
)

// PtermPrinter implements ConsolePrinter using pterm.
type PtermPrinter struct {
	info  *pterm.PrefixPrinter
	warn  *pterm.PrefixPrinter
	err   *pterm.PrefixPrinter
	ok    *pterm.PrefixPrinter
	plain *pterm.PrefixPrinter
}

func NewPtermPrinter() *PtermPrinter {
	return &PtermPrinter{
		info:  pterm.DefaultCenter.Sprint,
		warn:  pterm.DefaultCenter.Sprint,
		err:   pterm.DefaultCenter.Sprint,
		ok:    pterm.DefaultCenter.Sprint,
		plain: pterm.DefaultCenter.Sprint,
	}
}

// A simple implementation using pterm's convenience methods.
func (p *PtermPrinter) Info(format string, a ...interface{}) {
	pterm.Info.Printf(format+"\n", a...)
}
func (p *PtermPrinter) Warn(format string, a ...interface{}) {
	pterm.Warning.Printf(format+"\n", a...)
}
func (p *PtermPrinter) Error(format string, a ...interface{}) {
	pterm.Error.Printf(format+"\n", a...)
}
func (p *PtermPrinter) Success(format string, a ...interface{}) {
	pterm.Success.Printf(format+"\n", a...)
}
func (p *PtermPrinter) Printf(format string, a ...interface{}) {
	fmt.Printf(format+"\n", a...)
}
