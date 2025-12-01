package distro

import (
	"testing"

	"github.com/hashicorp/go-version"
)

func TestFromJSON(t *testing.T) {
	tests := []struct {
		name    string
		jsonStr string
		wantErr bool
	}{
		{
			name: "valid debian distro",
			jsonStr: `{
				"family": "debian",
				"name": "Ubuntu",
				"description": "Ubuntu 20.04 LTS",
				"version": "20.04",
				"distro_version": "20.04",
				"distro_codename": "focal"
			}`,
			wantErr: false,
		},
		{
			name: "valid arch distro",
			jsonStr: `{
				"family": "arch",
				"name": "Arch Linux",
				"description": "Arch Linux Rolling",
				"version": "1.0.0",
				"distro_version": "rolling",
				"distro_codename": ""
			}`,
			wantErr: false,
		},
		{
			name:    "invalid json",
			jsonStr: `{invalid}`,
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			d, err := FromJSON([]byte(tt.jsonStr))
			if (err != nil) != tt.wantErr {
				t.Errorf("FromJSON() error = %v, wantErr %v", err, tt.wantErr)
				return
			}
			if !tt.wantErr && d == nil {
				t.Error("FromJSON() returned nil distro without error")
			}
		})
	}
}

func TestDistro_ToJSON(t *testing.T) {
	ver, _ := version.NewVersion("20.04")
	d := &Distro{
		Family:         "debian",
		Name:           "Ubuntu",
		Description:    "Ubuntu 20.04 LTS",
		Version:        ver,
		DistroVersion:  "20.04",
		DistroCodename: "focal",
	}

	data, err := d.ToJSON()
	if err != nil {
		t.Errorf("ToJSON() error = %v", err)
		return
	}
	if len(data) == 0 {
		t.Error("ToJSON() returned empty data")
	}
}

func TestDistro_IsCompatible(t *testing.T) {
	tests := []struct {
		name           string
		distroVersion  string
		constraint     string
		wantCompatible bool
	}{
		{
			name:           "exact match",
			distroVersion:  "20.04",
			constraint:     "20.04",
			wantCompatible: true,
		},
		{
			name:           "greater than",
			distroVersion:  "22.04",
			constraint:     ">= 20.04",
			wantCompatible: true,
		},
		{
			name:           "less than",
			distroVersion:  "18.04",
			constraint:     ">= 20.04",
			wantCompatible: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ver, _ := version.NewVersion(tt.distroVersion)
			d := &Distro{Version: ver}

			constraints, err := version.NewConstraint(tt.constraint)
			if err != nil {
				t.Fatalf("Failed to create constraint: %v", err)
			}

			if got := d.IsCompatible(constraints); got != tt.wantCompatible {
				t.Errorf("IsCompatible() = %v, want %v", got, tt.wantCompatible)
			}
		})
	}
}
