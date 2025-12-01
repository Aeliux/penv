package index

import "github.com/hashicorp/go-version"

type RemoteDistroUrl3 struct {
	Url    string       `json:"url"`
	Hash   string       `json:"hash"`
	Size   int64        `json:"size"`
	Filter DistroFilter `json:"filter"`
}

type RemoteAddonUrl3 struct {
	Url    string      `json:"url"`
	Hash   string      `json:"hash"`
	Size   int64       `json:"size"`
	Filter AddonFilter `json:"filter"`
}

type RemoteDistro3 struct {
	Info Distro             `json:"info"`
	Urls []RemoteDistroUrl3 `json:"urls"`
}

type RemoteAddon3 struct {
	Info Addon             `json:"info"`
	Urls []RemoteAddonUrl3 `json:"urls"`
}

type RemoteIndex3 struct {
	Distros []RemoteDistro3 `json:"distros"`
	Addons  []RemoteAddon3  `json:"addons"`
}

func (ri *RemoteIndex3) GetCompatibleDistros(versionConstraints version.Constraints) []RemoteDistro3 {
	var compatibleDistros []RemoteDistro3
	for _, distro := range ri.Distros {
		if distro.Info.IsCompatible(versionConstraints) {
			for _, url := range distro.Urls {
				if url.Filter.Matches() {
					compatibleDistros = append(compatibleDistros, distro)
					break
				}
			}
		}
	}
	return compatibleDistros
}

func (ri *RemoteIndex3) GetCompatibleAddons(distro *Distro) []RemoteAddon3 {
	var compatibleAddons []RemoteAddon3
	for _, addon := range ri.Addons {
		for _, url := range addon.Urls {
			if url.Filter.Matches(distro) {
				compatibleAddons = append(compatibleAddons, addon)
				break
			}
		}
	}
	return compatibleAddons
}
