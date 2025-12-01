package console

// ConsolePrinter defines UI methods libraries can call.
// Implementations can be simple (Printf/Info/Error) or complex (Progress, Table).
type ConsolePrinter interface {
	Info(format string, a ...interface{})
	Warn(format string, a ...interface{})
	Error(format string, a ...interface{})
	Success(format string, a ...interface{})
	Printf(format string, a ...interface{})
	// Optionally add progress/spinner/table methods as needed
}

// default no-op console that discards everything
type noopConsole struct{}

func (noopConsole) Info(string, ...interface{})    {}
func (noopConsole) Warn(string, ...interface{})    {}
func (noopConsole) Error(string, ...interface{})   {}
func (noopConsole) Success(string, ...interface{}) {}
func (noopConsole) Printf(string, ...interface{})  {}

// Out is the console used by libraries. Default is no-op.
// Main app calls Set(...) to enable a real console implementation.
var Out ConsolePrinter = noopConsole{}

// Set installs a ConsolePrinter implementation (e.g., a pterm-based printer)
func Set(c ConsolePrinter) {
	if c == nil {
		Out = noopConsole{}
	} else {
		Out = c
	}
}
