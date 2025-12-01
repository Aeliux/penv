package common

import (
	"encoding/json"

	"github.com/hashicorp/go-version"
)

type Distro struct {
	Family         string           `json:"family"`
	Name           string           `json:"name"`
	Description    string           `json:"description"`
	Version        *version.Version `json:"version"`
	DistroVersion  string           `json:"distro_version"`
	DistroCodename string           `json:"distro_codename"`
}

func (d *Distro) ToJson() ([]byte, error) {
	return json.Marshal(d)
}

func (d *Distro) IsCompatible(versionConstraints version.Constraints) bool {
	return versionConstraints.Check(d.Version)
}

// GetDistroFromJSON parses a JSON byte slice into a Distro struct.
func GetDistroFromJSON(data []byte) (*Distro, error) {
	distro := &Distro{}
	err := json.Unmarshal(data, distro)
	if err != nil {
		return nil, err
	}
	return distro, nil
}
