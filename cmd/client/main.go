package main

import (
	"fmt"
	"log"

	"github.com/aeliux/penv/pkg/distro"
)

func main() {
	jsonData := []byte(`{
		"family": "debian",
		"name": "Ubuntu",
		"description": "Ubuntu 20.04 LTS",
		"version": "20.04",
		"distro_version": "20.04",
		"distro_codename": "focal"
	}`)

	d, err := distro.FromJSON(jsonData)
	if err != nil {
		log.Fatalf("Error parsing distro JSON: %v", err)
	}

	fmt.Printf("Distro Name: %s\n", d.Name)
	fmt.Printf("Distro Version: %s\n", d.Version.String())
}
