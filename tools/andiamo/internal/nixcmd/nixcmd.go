// Package nixcmd wraps the nix invocations andiamo drives: building
// derivations, querying closures, and copying closures to hosts.
package nixcmd

import (
	"context"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"regexp"
	"strings"
	"syscall"
	"time"
)

var ansiRE = regexp.MustCompile("\x1b\\[[0-9;]*m")

func command(ctx context.Context, name string, args ...string) *exec.Cmd {
	cmd := exec.CommandContext(ctx, name, args...)
	cmd.Cancel = func() error { return cmd.Process.Signal(syscall.SIGINT) } // nix aborts cleanly on INT
	cmd.WaitDelay = 3 * time.Second                                         // then KILL
	return cmd
}

func run(ctx context.Context, extraEnv []string, name string, args ...string) (string, error) {
	cmd := command(ctx, name, args...)
	cmd.Env = append(os.Environ(), extraEnv...)
	var stderr strings.Builder
	cmd.Stderr = &stderr
	out, err := cmd.Output()
	if err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg != "" {
			lines := strings.Split(msg, "\n")
			return "", fmt.Errorf("%s %s: %s", name, args[0], lines[len(lines)-1])
		}
		return "", fmt.Errorf("%s %s: %w", name, args[0], err)
	}
	return strings.TrimSpace(string(out)), nil
}

// Build realizes the given derivations' out outputs in a single nix
// invocation (nix parallelizes internally; fanning out at this layer
// would only contend on the daemon) and returns their out paths in
// order. Building by .drv path skips the per-installable flake eval
// nix would otherwise run serially inside the build — the inventory
// eval already paid for it. A derivation that already built (or a
// nixos test that already passed) is a cache hit.
//
// Progress is read from nix's internal-json log: every event is
// passed to on as it arrives (from the child's copy goroutine).
// Errors and warnings are retained, so a failed build's error is
// nix's own "builder for '…' failed … last N log lines" text.
func Build(ctx context.Context, drvs []string, on func(Event)) ([]string, error) {
	args := []string{"build", "--no-link", "--print-out-paths", "--log-format", "internal-json"}
	for _, d := range drvs {
		args = append(args, d+"^out")
	}
	cmd := command(ctx, "nix", args...)
	var kept []string
	stderr := &LineWriter{Fn: func(s string) {
		if js, ok := strings.CutPrefix(s, "@nix "); ok {
			var e Event
			if json.Unmarshal([]byte(js), &e) == nil {
				if e.Action == "msg" && e.Level <= 1 {
					kept = append(kept, ansiRE.ReplaceAllString(e.Msg, ""))
				}
				if on != nil {
					on(e)
				}
				return
			}
		}
		kept = append(kept, s)
	}}
	cmd.Stderr = stderr
	out, err := cmd.Output()
	stderr.Flush()
	if err != nil {
		if msg := strings.TrimSpace(strings.Join(kept, "\n")); msg != "" {
			return nil, fmt.Errorf("nix build: %s", msg)
		}
		return nil, fmt.Errorf("nix build: %w", err)
	}
	lines := strings.Split(strings.TrimSpace(string(out)), "\n")
	if len(lines) != len(drvs) {
		return nil, fmt.Errorf("built %d paths, expected %d", len(lines), len(drvs))
	}
	for i := range lines {
		lines[i] = strings.TrimSpace(lines[i])
	}
	return lines, nil
}

// Closure lists everything realizing drv can build or fetch: every
// .drv in its closure plus their output paths. The outputs are read
// from the .drv files themselves — nix-store's --include-outputs only
// reports outputs that already exist, and the missing ones are the
// point. A store database query plus a few thousand small file reads:
// well under a second for a system toplevel.
func Closure(ctx context.Context, drv string) ([]string, error) {
	out, err := run(ctx, nil, "nix-store", "-qR", drv)
	if err != nil {
		return nil, err
	}
	paths := strings.Split(out, "\n")
	all := make([]string, 0, 2*len(paths))
	for _, p := range paths {
		all = append(all, p)
		if strings.HasSuffix(p, ".drv") {
			if data, err := os.ReadFile(p); err == nil {
				all = append(all, drvOutputs(data)...)
			}
		}
	}
	return all, nil
}

var drvOutputRE = regexp.MustCompile(`\("[^"]*","(/nix/store/[^"]+)"`)

// drvOutputs extracts the output paths from a .drv file's ATerm
// header: Derive([("out","/nix/store/…","",""),…],… — the outputs
// list is the first element, terminated by the first "]".
func drvOutputs(data []byte) []string {
	s, ok := strings.CutPrefix(string(data), "Derive([")
	if !ok {
		return nil
	}
	end := strings.IndexByte(s, ']')
	if end < 0 {
		return nil
	}
	var outs []string
	for _, m := range drvOutputRE.FindAllStringSubmatch(s[:end], -1) {
		outs = append(outs, m[1])
	}
	return outs
}

// Copy pushes a closure to a host over ssh. The legacy ssh:// store is
// deliberate: it accepts unsigned locally-built paths from a trusted
// user (same as nixos-rebuild --target-host), where ssh-ng:// rejects
// them for lacking a trusted signature.
func Copy(ctx context.Context, host, path string) error {
	env := []string{"NIX_SSHOPTS=-o BatchMode=yes -o ConnectTimeout=10"}
	_, err := run(ctx, env, "nix", "copy", "--to", "ssh://"+host, path)
	return err
}

// CopyFrom pulls a closure from a host back into the local store —
// used to diff against a running system the local store no longer
// holds. The legacy ssh:// store mirrors Copy, and --no-check-sigs is
// its trust model in the other direction: fleet paths are locally
// built and unsigned, and the operator is a trusted user on both ends.
func CopyFrom(ctx context.Context, host, path string) error {
	env := []string{"NIX_SSHOPTS=-o BatchMode=yes -o ConnectTimeout=10"}
	_, err := run(ctx, env, "nix", "copy", "--no-check-sigs", "--from", "ssh://"+host, path)
	return err
}
