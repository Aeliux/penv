package index

import (
	"regexp"
	"runtime"
)

// matchesPattern is a helper that handles empty patterns and regex matching
func matchesPattern(pattern, value string) bool {
	if pattern == "" {
		return true
	}
	matched, err := regexp.MatchString(pattern, value)
	return err == nil && matched
}

// matchesArch checks if the current architecture matches the pattern
func matchesArch(pattern string) bool {
	return matchesPattern(pattern, runtime.GOARCH)
}

type DistroFilter struct {
	Architecture string `json:"architecture"`
}

func (df *DistroFilter) Matches() bool {
	return matchesArch(df.Architecture)
}

type AddonFilter struct {
	Architecture string `json:"architecture"`
	Family       string `json:"family"`
	Name         string `json:"name"`
	Version      string `json:"version"`
}

func (af *AddonFilter) Matches(distro *Distro) bool {
	// Early return pattern - idiomatic Go
	if !matchesArch(af.Architecture) {
		return false
	}
	if !matchesPattern(af.Family, distro.Family) {
		return false
	}
	if !matchesPattern(af.Name, distro.Name) {
		return false
	}
	if !matchesPattern(af.Version, distro.Version.String()) {
		return false
	}
	return true
}
