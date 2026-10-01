package gomin

import (
	"net"
	"os"
	"regexp"
	"runtime"
	"testing"
	"time"
)

// go.mod says go 1.27.0 and toolchain go1.27.1: go-ci must install the toolchain line.
func TestToolchainLine(t *testing.T) {
	mod, err := os.ReadFile("go.mod")
	if err != nil {
		t.Fatal(err)
	}
	m := regexp.MustCompile(`(?m)^toolchain (go\S+)`).FindSubmatch(mod)
	if m == nil {
		t.Fatal("go.mod has no toolchain line")
	}
	if got := runtime.Version(); got != string(m[1]) {
		t.Fatalf("tests run on %s, go.mod toolchain line says %s", got, m[1])
	}
}

func TestAdd(t *testing.T) {
	if Add(2, 2) != 4 {
		t.Fatal("2+2 != 4")
	}
}

func dial(t *testing.T, env string) error {
	t.Helper()
	hp, err := HostPort(os.Getenv(env))
	if err != nil {
		t.Fatalf("%s: %v", env, err)
	}
	c, err := net.DialTimeout("tcp", hp, 3*time.Second)
	if err == nil {
		_ = c.Close()
	}
	return err
}

// The self-test sets postgres-image only: Postgres must be up, the empty Redis service skipped.
func TestServices(t *testing.T) {
	if os.Getenv("EXPECT_SERVICES") != "1" {
		t.Skip("services not requested")
	}
	if err := dial(t, "CI_POSTGRES_URL"); err != nil {
		t.Fatalf("postgres unreachable: %v", err)
	}
	if err := dial(t, "CI_REDIS_URL"); err == nil {
		t.Fatal("redis is reachable although redis-image is empty")
	}
}
