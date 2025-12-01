package distro

import (
	"encoding/json"

	"github.com/hashicorp/go-version"
)

// Distro represents a Linux distribution with its metadata and version information.
type Distro struct {
	Family         string           `json:"family"`
	Name           string           `json:"name"`
	Description    string           `json:"description"`
	Version        *version.Version `json:"version"`
	DistroVersion  string           `json:"distro_version"`
	DistroCodename string           `json:"distro_codename"`
}

// ToJSON serializes a Distro struct to JSON bytes.
func (d *Distro) ToJSON() ([]byte, error) {
	return json.Marshal(d)
}

// IsCompatible checks if the distro version satisfies the given version constraints.
func (d *Distro) IsCompatible(versionConstraints version.Constraints) bool {
	return versionConstraints.Check(d.Version)
}

// FromJSON parses a JSON byte slice into a Distro struct.
func FromJSON(data []byte) (*Distro, error) {
	distro := &Distro{}
	err := json.Unmarshal(data, distro)
	if err != nil {
		return nil, err
	}
	return distro, nil
}
