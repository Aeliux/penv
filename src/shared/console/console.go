package console

// ConsolePrinter defines UI methods libraries can call.
// Implementations can be simple (Printf/Info/Error) or complex (Progress, Table).
type ConsolePrinter interface {
	Info(format string, a ...any)
	Warn(format string, a ...any)
	Error(format string, a ...any)
	Success(format string, a ...any)
	Printf(format string, a ...any)
	// Optionally add progress/spinner/table methods as needed
}

// default no-op console that discards everything
type noopConsole struct{}

func (noopConsole) Info(string, ...any)    {}
func (noopConsole) Warn(string, ...any)    {}
func (noopConsole) Error(string, ...any)   {}
func (noopConsole) Success(string, ...any) {}
func (noopConsole) Printf(string, ...any)  {}

// Out is the console used by libraries. Default is no-op.
// Main app calls Set(...) to enable a real console implementation.
var Out ConsolePrinter = noopConsole{}

// Set installs a ConsolePrinter implementation (e.g., a pterm-based printer).
// Pass nil to disable console output entirely.
func Set(c ConsolePrinter) {
	if c == nil {
		Out = noopConsole{}
	} else {
		Out = c
	}
}

// Get returns the current console printer.
func Get() ConsolePrinter {
	return Out
}

// Reset restores the console to the default no-op implementation.
func Reset() {
	Out = noopConsole{}
}
