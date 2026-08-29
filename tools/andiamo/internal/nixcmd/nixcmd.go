// Package nixcmd wraps the nix invocations andiamo drives: building
// toplevels and check gates, and copying closures to hosts.
package nixcmd

import (
	"context"
	"fmt"
	"os"
	"os/exec"
	"strings"
	"syscall"
	"time"
)

func run(ctx context.Context, extraEnv []string, args ...string) (string, error) {
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Cancel = func() error { return cmd.Process.Signal(syscall.SIGINT) } // nix aborts cleanly on INT
	cmd.WaitDelay = 3 * time.Second                                         // then KILL
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

// runLive mirrors nix's own live progress bar to the terminal instead
// of capturing it; stdout is still returned. Use only while no other
// live renderer owns the terminal.
func runLive(ctx context.Context, args ...string) (string, error) {
	args = append(args, "--log-format", "bar")
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Cancel = func() error { return cmd.Process.Signal(syscall.SIGINT) } // nix aborts cleanly on INT
	cmd.WaitDelay = 3 * time.Second                                         // then KILL
	cmd.Stderr = os.Stderr
	out, err := cmd.Output()
	if err != nil {
		return "", fmt.Errorf("nix %s failed (see log above)", args[0])
	}
	return strings.TrimSpace(string(out)), nil
}

// Build realizes the given derivations' out outputs in a single nix
// invocation (nix parallelizes internally; fanning out at this layer
// would only contend on the daemon) and returns their out paths in
// order. Building by .drv path skips the per-installable flake eval
// nix would otherwise run serially inside the build — the inventory
// eval already paid for it. A derivation that already built (or a
// nixos test that already passed) is a cache hit. live streams nix's
// progress bar to the terminal.
func Build(ctx context.Context, drvs []string, live bool) ([]string, error) {
	args := []string{"build", "--no-link", "--print-out-paths"}
	for _, d := range drvs {
		args = append(args, d+"^out")
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
	if len(lines) != len(drvs) {
		return nil, fmt.Errorf("built %d paths, expected %d", len(lines), len(drvs))
	}
	for i := range lines {
		lines[i] = strings.TrimSpace(lines[i])
	}
	return lines, nil
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
