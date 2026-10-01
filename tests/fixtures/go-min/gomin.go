// Package gomin is the fixture for the ci-templates self-test.
package gomin

import (
	"fmt"
	"net/url"
)

// Add returns a + b.
func Add(a, b int) int { return a + b }

// HostPort extracts host:port from a service URL.
func HostPort(raw string) (string, error) {
	u, err := url.Parse(raw)
	if err != nil {
		return "", err
	}
	if u.Port() == "" {
		return "", fmt.Errorf("no port in %q", raw)
	}
	return u.Host, nil
}
