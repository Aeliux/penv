package main

import "penv/shared/console"

func main() {
	// Set up the pterm console printer
	console.Set(console.NewPtermPrinter())

	console.Out.Info("Application started")
	console.Out.Success("Setup complete")
}
