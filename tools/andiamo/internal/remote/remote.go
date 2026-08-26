// Package remote runs commands on fleet hosts, over ssh or directly
// when the target is the machine andiamo is running on. It relies on
// the operator's real ssh (config, agent, known_hosts) rather than a
// Go ssh implementation.
package remote

import (
	"context"
	"fmt"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"time"

	"github.com/kylerisse/nixcfg/tools/andiamo/internal/plan"
)

// Target addresses one host.
type Target struct {
	Host    string
	Local   bool
	Timeout time.Duration // ssh connect timeout
}

// Run executes a shell script on the target and returns trimmed stdout.
func (t Target) Run(ctx context.Context, script string) (string, error) {
	var cmd *exec.Cmd
	if t.Local {
		cmd = exec.CommandContext(ctx, "sh", "-c", script)
	} else {
		secs := int(t.Timeout.Seconds())
		if secs < 1 {
			secs = 5
		}
		cmd = exec.CommandContext(ctx, "ssh",
			"-o", "BatchMode=yes",
			"-o", fmt.Sprintf("ConnectTimeout=%d", secs),
			t.Host, script)
	}
	out, err := cmd.CombinedOutput()
	text := strings.TrimSpace(string(out))
	if err != nil {
		if text != "" {
			return "", fmt.Errorf("%s: %s", err, lastLine(text))
		}
		return "", err
	}
	return text, nil
}

func lastLine(s string) string {
	lines := strings.Split(s, "\n")
	return lines[len(lines)-1]
}

// probePaths are resolved in order by Probe. The first three identify
// the system generations; the rest are the boot-critical links of the
// running and booted systems.
var probePaths = []string{
	"/run/current-system",
	"/run/booted-system",
	"/nix/var/nix/profiles/system",
	"/run/current-system/kernel",
	"/run/current-system/initrd",
	"/run/current-system/kernel-modules",
	"/run/current-system/systemd",
	"/run/booted-system/kernel",
	"/run/booted-system/initrd",
	"/run/booted-system/kernel-modules",
	"/run/booted-system/systemd",
}

// probeScript resolves probePaths, then prints one line each for: the
// generation name (unresolved link), the profile symlink mtime (store
// paths carry no dates; the symlink records when the profile was set),
// the running system's version string, uptime in whole seconds, and
// the booted kernel release. Each value is captured and echoed so a
// file without a trailing newline (nixos-version) or a failing command
// still yields exactly one line.
var probeScript = "for p in " + strings.Join(probePaths, " ") +
	`; do readlink -f "$p" 2>/dev/null || echo MISSING; done; ` +
	`readlink /nix/var/nix/profiles/system 2>/dev/null || echo MISSING; ` +
	`stat -c %Y /nix/var/nix/profiles/system 2>/dev/null || echo 0; ` +
	`v=$(cat /run/current-system/nixos-version 2>/dev/null); echo "${v:-MISSING}"; ` +
	`v=$(cut -d. -f1 /proc/uptime 2>/dev/null); echo "${v:-0}"; ` +
	`v=$(uname -r 2>/dev/null); echo "${v:-MISSING}"`

// probeExtra is the number of lines probeScript prints after probePaths.
const probeExtra = 5

// Probe reads the target's system symlinks plus generation, deploy
// time, version, uptime, and kernel in one round trip.
func Probe(ctx context.Context, t Target) plan.Probe {
	out, err := t.Run(ctx, probeScript)
	if err != nil {
		return plan.Probe{Err: err}
	}
	return parseProbe(out)
}

// parseProbe maps probeScript's output positionally onto a Probe.
func parseProbe(out string) plan.Probe {
	lines := strings.Split(out, "\n")
	want := len(probePaths) + probeExtra
	if len(lines) != want {
		return plan.Probe{Err: fmt.Errorf("probe returned %d lines, want %d", len(lines), want)}
	}
	get := func(i int) string {
		v := strings.TrimSpace(lines[i])
		if v == "MISSING" {
			return ""
		}
		return v
	}
	n := len(probePaths)
	deployedAt, _ := strconv.ParseInt(get(n+1), 10, 64)
	uptime, _ := strconv.ParseInt(get(n+3), 10, 64)
	return plan.Probe{
		Current: get(0),
		Booted:  get(1),
		Profile: get(2),
		CurrentLinks: plan.Links{
			Kernel: get(3), Initrd: get(4), KernelModules: get(5), Systemd: get(6),
		},
		BootedLinks: plan.Links{
			Kernel: get(7), Initrd: get(8), KernelModules: get(9), Systemd: get(10),
		},
		Generation:   plan.ParseGeneration(get(n)),
		DeployedAt:   deployedAt,
		NixosVersion: get(n + 2),
		UptimeSec:    uptime,
		Kernel:       get(n + 4),
	}
}

// LocalLinks resolves the boot-critical links of a toplevel present in
// the local store (used for the reboot decision before anything is
// activated remotely).
func LocalLinks(toplevel string) plan.Links {
	resolve := func(name string) string {
		p, err := filepath.EvalSymlinks(filepath.Join(toplevel, name))
		if err != nil {
			return ""
		}
		return p
	}
	return plan.Links{
		Kernel:        resolve("kernel"),
		Initrd:        resolve("initrd"),
		KernelModules: resolve("kernel-modules"),
		Systemd:       resolve("systemd"),
	}
}

// Activate sets the system profile to toplevel and runs
// switch-to-configuration with the given mode ("switch" or "boot").
// This mirrors what nixos-rebuild --target-host does, minus the
// per-host flake re-evaluation.
func Activate(ctx context.Context, t Target, toplevel, mode string) error {
	script := fmt.Sprintf(
		"sudo nix-env -p /nix/var/nix/profiles/system --set %s && sudo %s/bin/switch-to-configuration %s",
		toplevel, toplevel, mode)
	_, err := t.Run(ctx, script)
	return err
}

// Reboot asks the target to reboot. The dropped connection makes the
// ssh exit status meaningless, so errors are ignored.
func Reboot(ctx context.Context, t Target) {
	_, _ = t.Run(ctx, "sudo systemctl reboot")
}

// WaitForBoot polls until the target reports /run/booted-system ==
// expected, or the deadline passes. A host that comes back on a
// different generation (bootloader fallback) is an explicit error.
func WaitForBoot(ctx context.Context, t Target, expected string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	// Give the host a moment to actually go down before probing, so we
	// don't read the old system pre-shutdown and call it a success.
	select {
	case <-time.After(15 * time.Second):
	case <-ctx.Done():
		return ctx.Err()
	}
	sawDown := false
	afterDown := ""
	for time.Now().Before(deadline) {
		out, err := t.Run(ctx, "readlink -f /run/booted-system")
		if err != nil {
			sawDown = true
			afterDown = ""
		} else {
			if out == expected {
				return nil
			}
			if sawDown {
				// The host went down and answered again, but on the
				// wrong generation: bootloader fallback. No amount of
				// waiting fixes that.
				afterDown = out
			}
		}
		select {
		case <-time.After(5 * time.Second):
		case <-ctx.Done():
			return ctx.Err()
		}
	}
	if afterDown != "" {
		return fmt.Errorf("host came back on %s instead of the deployed system", filepath.Base(afterDown))
	}
	return fmt.Errorf("no answer within %s", timeout)
}

// CurrentSystem reads /run/current-system, used to verify a switch.
func CurrentSystem(ctx context.Context, t Target) (string, error) {
	return t.Run(ctx, "readlink -f /run/current-system")
}
