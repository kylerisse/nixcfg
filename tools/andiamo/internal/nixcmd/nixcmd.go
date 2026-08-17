// Package nixcmd wraps the nix invocations andiamo drives: building
// toplevels and check gates, and copying closures to hosts.
package nixcmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
)

func run(ctx context.Context, extraEnv []string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Env = append(os.Environ(), extraEnv...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			lines := strings.Split(msg, "\n")
			return "", fmt.Errorf("nix %s: %s", args[0], lines[len(lines)-1])
		}
		return "", fmt.Errorf("nix %s: %w", args[0], err)
	}
	return strings.TrimSpace(string(out)), nil
}

// runLive mirrors nix's own live progress (bar with streaming log
// lines) to the terminal instead of capturing it; stdout is still
// returned. Use only while no other live renderer owns the terminal.
func runLive(ctx context.Context, args ...string) (string, error) {
	args = append(args, "--log-format", "bar-with-logs")
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("nix %s failed (see log above)", args[0])
	}
	return strings.TrimSpace(string(out)), nil
}

// BuildToplevels builds the system toplevels for the given hosts in a
// single nix invocation (nix parallelizes internally; fanning out at
// this layer would only contend on the daemon). live streams nix's
// progress bar to the terminal. Returns host→outPath.
func BuildToplevels(ctx context.Context, flakePath string, hosts []string, live bool) (map[string]string, error) {
	args := []string{"build", "--no-link", "--print-out-paths"}
	for _, h := range hosts {
		args = append(args, fmt.Sprintf("%s#nixosConfigurations.%s.config.system.build.toplevel", flakePath, h))
	}
	var out string
	var err error
	if live {
		out, err = runLive(ctx, args...)
	} else {
		out, err = run(ctx, nil, args...)
	}
	if err != nil {
		return nil, err
	}
	lines := strings.Split(out, "\n")
	if len(lines) != len(hosts) {
		return nil, fmt.Errorf("built %d toplevels, expected %d", len(lines), len(hosts))
	}
	paths := make(map[string]string, len(hosts))
	for i, h := range hosts {
		paths[h] = strings.TrimSpace(lines[i])
	}
	return paths, nil
}

// BuildChecks realizes the given flake checks (x86_64-linux, the only
// system with checks in this flake). A check that already passed at
// this eval is a cache hit. live streams nix's progress bar.
func BuildChecks(ctx context.Context, flakePath string, checks []string, live bool) error {
	args := []string{"build", "--no-link"}
	for _, c := range checks {
		args = append(args, fmt.Sprintf("%s#checks.x86_64-linux.%s", flakePath, c))
	}
	var err error
	if live {
		_, err = runLive(ctx, args...)
	} else {
		_, err = run(ctx, nil, args...)
	}
	return err
}

// Copy pushes a closure to a host over ssh. The legacy ssh:// store is
// deliberate: it accepts unsigned locally-built paths from a trusted
// user (same as nixos-rebuild --target-host), where ssh-ng:// rejects
// them for lacking a trusted signature.
func Copy(ctx context.Context, host, path string) error {
	env := []string{"NIX_SSHOPTS=-o BatchMode=yes -o ConnectTimeout=10"}
	_, err := run(ctx, env, "copy", "--to", "ssh://"+host, path)
	return err
}
