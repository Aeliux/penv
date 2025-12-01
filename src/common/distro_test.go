package common

import "testing"

var jsonData = []byte(`{
		"family": "debian",
		"name": "Ubuntu",
		"description": "Ubuntu 20.04 LTS",
		"version": "3.0.14",
		"distro_version": "20.04",
		"distro_codename": "focal"
	}`)

func TestDistro(t *testing.T) {
	// Load the distro from JSON
	distro, err := GetDistroFromJSON(jsonData)
	if err != nil {
		t.Fatalf("Error parsing distro JSON: %v", err)
	}

	// Validate the fields
	if distro.Name != "Ubuntu" {
		t.Errorf("Expected Name to be 'Ubuntu', got '%s'", distro.Name)
	}

	if distro.Version.String() != "3.0.14" {
		t.Errorf("Expected Version to be '3.0.14', got '%s'", distro.Version.String())
	}

	if distro.Family != "debian" {
		t.Errorf("Expected Family to be 'debian', got '%s'", distro.Family)
	}

	if distro.DistroCodename != "focal" {
		t.Errorf("Expected DistroCodename to be 'focal', got '%s'", distro.DistroCodename)
	}

	jsonOutput, err := distro.ToJson()
	if err != nil {
		t.Fatalf("Error converting distro to JSON: %v", err)
	}

	distroFromJson, err := GetDistroFromJSON(jsonOutput)
	if err != nil {
		t.Fatalf("Error parsing distro JSON from ToJson output: %v", err)
	}

	if distro != distroFromJson {
		t.Errorf("Distro from ToJson does not match original")
	}
}
