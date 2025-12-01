package index

import (
	"encoding/json"

	"github.com/hashicorp/go-version"
)

type Addon struct {
	Name        string           `json:"name"`
	Description string           `json:"description"`
	Version     *version.Version `json:"version"`
}

func (a *Addon) ToJson() ([]byte, error) {
	return json.Marshal(a)
}

func AddonFromJson(data []byte) (*Addon, error) {
	addon := &Addon{}
	err := json.Unmarshal(data, addon)
	if err != nil {
		return nil, err
	}
	return addon, nil
}
