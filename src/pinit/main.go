package main

import (
	"fmt"
	"log"

	"penv/shared/distro"
)

func main() {
	// Example pinit functionality
	jsonData := []byte(`{
		"family": "arch",
		"name": "Arch Linux",
		"description": "Arch Linux Rolling Release",
		"version": "1.0.0",
		"distro_version": "rolling",
		"distro_codename": ""
	}`)

	d, err := distro.FromJSON(jsonData)
	if err != nil {
		log.Fatalf("Error parsing distro JSON: %v", err)
	}

	fmt.Printf("Initializing penv for %s...\n", d.Name)
	fmt.Printf("Family: %s, Version: %s\n", d.Family, d.Version.String())
}
