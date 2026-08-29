// Package flake derives the fleet inventory and deployment policy from
// the flake itself — nothing is hardcoded about the hosts. Per-host
// facts are evaluated in parallel nix processes and memoized in a
// disposable content-keyed cache: a pure flake eval is a function of
// the tracked tree content (incl. flake.lock), so HEAD + `git diff
// HEAD` + the nix version + the eval expression key everything the
// eval can see.
package flake

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"github.com/kylerisse/nixcfg/tools/andiamo/internal/plan"
)

// hostExpr maps one nixosConfiguration to the facts andiamo needs.
// Per-host policy lives in the host's own config as
// `_module.args.andiamo = { checks = [...]; rebootLast = true; }`
// (nixinate-style; absent attrs default). The module system strips
// _module out of config, so the args are read from the eval result's
// sibling _module attr. outPath is computed at eval time; nothing gets
// built.
const hostExpr = `c: let a = c._module.args.andiamo or { }; in {
  toplevel = c.config.system.build.toplevel.outPath;
  toplevelDrv = c.config.system.build.toplevel.drvPath;
  system = c.pkgs.stdenv.hostPlatform.system;
  sshable = c.config.mynixcfg.ssh-server.enable;
  hostName = c.config.networking.hostName;
  nixosVersion = c.config.system.nixos.label;
  kernel = c.config.boot.kernelPackages.kernel.modDirVersion;
  checks = a.checks or [ ];
  rebootLast = a.rebootLast or false;
}`

// checkExpr resolves one flake check to its derivation and output.
// Deliberately not named drvPath/outPath: nix eval --json collapses
// any attrset carrying outPath to a bare string.
const checkExpr = `c: { drv = c.drvPath; out = c.outPath; }`

type facts struct {
	Toplevel     string   `json:"toplevel"`
	ToplevelDrv  string   `json:"toplevelDrv"`
	System       string   `json:"system"`
	Sshable      bool     `json:"sshable"`
	HostName     string   `json:"hostName"`
	NixosVersion string   `json:"nixosVersion"` // system.nixos.label: what /run/current-system/nixos-version holds
	Kernel       string   `json:"kernel"`       // modDirVersion: what uname -r reports
	Checks       []string `json:"checks"`
	RebootLast   bool     `json:"rebootLast"`
}

type checkFacts struct {
	Drv string `json:"drv"`
	Out string `json:"out"`
}

// HostNames lists the nixosConfigurations without forcing any of them
// — this is near-instant regardless of fleet size.
func HostNames(ctx context.Context, flakePath string) ([]string, error) {
	out, err := nixEval(ctx, flakePath+"#nixosConfigurations", nil, "--apply", "builtins.attrNames")
	if err != nil {
		return nil, fmt.Errorf("listing nixosConfigurations: %w", err)
	}
	var names []string
	if err := json.Unmarshal(out, &names); err != nil {
		return nil, fmt.Errorf("parsing host names: %w", err)
	}
	return names, nil
}

// Inventory accumulates per-host facts from cache and parallel evals.
type Inventory struct {
	flakePath string
	jobs      int
	key       string // "" disables caching
	dir       string
	mu        sync.Mutex
	facts     map[string]facts
	checks    map[string]checkFacts
}

// Open prepares an inventory. Caching is silently disabled when the
// cache key can't be computed (e.g. no git) or noCache is set.
func Open(flakePath string, jobs int, noCache bool) *Inventory {
	if jobs < 1 {
		jobs = 1
	}
	inv := &Inventory{
		flakePath: flakePath,
		jobs:      jobs,
		facts:     map[string]facts{},
		checks:    map[string]checkFacts{},
	}
	if base, err := os.UserCacheDir(); err == nil {
		inv.dir = filepath.Join(base, "andiamo")
	}
	if !noCache && inv.dir != "" {
		if key, err := treeKey(flakePath); err == nil {
			inv.key = key
		}
	}
	return inv
}

// Cached loads whatever the cache holds for names and reports which
// hosts still need a live eval. A cached record whose .drv has since
// been garbage-collected is a miss: the build phase needs the file,
// and a re-eval writes it back.
func (inv *Inventory) Cached(names []string) (have, missing []string) {
	for _, n := range names {
		if inv.key != "" {
			if f, ok := loadCached(inv.dir, inv.key, n); ok && exists(f.ToplevelDrv) {
				inv.facts[n] = f
				have = append(have, n)
				continue
			}
		}
		missing = append(missing, n)
	}
	return have, missing
}

// CachedChecks is Cached for flake checks.
func (inv *Inventory) CachedChecks(names []string) (have, missing []string) {
	for _, n := range names {
		if inv.key != "" {
			if f, ok := loadCachedCheck(inv.dir, inv.key, n); ok && exists(f.Drv) {
				inv.checks[n] = f
				have = append(have, n)
				continue
			}
		}
		missing = append(missing, n)
	}
	return have, missing
}

func exists(path string) bool {
	_, err := os.Stat(path)
	return err == nil
}

// EvalProgress carries optional callbacks so the caller can render
// per-host eval progress without this package knowing about the UI.
type EvalProgress struct {
	Start func(name string)
	Done  func(name string, err error)
	// Line receives each line nix writes to stderr while evaluating
	// name, as it arrives — with -v that is one "evaluating file …"
	// per file, thousands per host. Called from the child's copy
	// goroutine; must be cheap and safe to call concurrently.
	Line func(name, text string)
}

// Eval evaluates the given hosts in parallel nix processes (bounded by
// jobs) and stores the results in memory and, when caching is active,
// on disk.
func (inv *Inventory) Eval(ctx context.Context, names []string, p EvalProgress) error {
	return inv.evalAll(ctx, names, p, func(n string, line func(string)) error {
		out, err := nixEval(ctx, fmt.Sprintf("%s#nixosConfigurations.%s", inv.flakePath, n), line, "--apply", hostExpr)
		if err != nil {
			return err
		}
		var f facts
		if err := json.Unmarshal(out, &f); err != nil {
			return err
		}
		inv.mu.Lock()
		defer inv.mu.Unlock()
		inv.facts[n] = f
		if inv.key != "" {
			storeCached(inv.dir, inv.key, n, f)
		}
		return nil
	})
}

// EvalChecks resolves the named flake checks (x86_64-linux, the only
// system with checks in this flake) the same way Eval resolves hosts.
func (inv *Inventory) EvalChecks(ctx context.Context, names []string, p EvalProgress) error {
	return inv.evalAll(ctx, names, p, func(n string, line func(string)) error {
		out, err := nixEval(ctx, fmt.Sprintf("%s#checks.x86_64-linux.%s", inv.flakePath, n), line, "--apply", checkExpr)
		if err != nil {
			return err
		}
		var f checkFacts
		if err := json.Unmarshal(out, &f); err != nil {
			return err
		}
		if f.Drv == "" || f.Out == "" {
			return fmt.Errorf("check %s did not resolve to a derivation", n)
		}
		inv.mu.Lock()
		defer inv.mu.Unlock()
		inv.checks[n] = f
		if inv.key != "" {
			storeCachedCheck(inv.dir, inv.key, n, f)
		}
		return nil
	})
}

// evalAll runs do for every name, at most jobs at a time, wiring the
// progress callbacks and honouring cancellation. do must record its
// own result before returning, so a caller acting on Done never sees
// the entry missing.
func (inv *Inventory) evalAll(ctx context.Context, names []string, p EvalProgress, do func(n string, line func(string)) error) error {
	if len(names) == 0 {
		return nil
	}
	sem := make(chan struct{}, inv.jobs)
	var wg sync.WaitGroup
	var firstErr error
	for _, n := range names {
		wg.Add(1)
		go func(n string) {
			defer wg.Done()
			select {
			case sem <- struct{}{}:
			case <-ctx.Done():
				// Interrupted while queued: don't spawn a doomed nix.
				if p.Done != nil {
					p.Done(n, ctx.Err())
				}
				inv.mu.Lock()
				defer inv.mu.Unlock()
				if firstErr == nil {
					firstErr = fmt.Errorf("evaluating %s: %w", n, ctx.Err())
				}
				return
			}
			defer func() { <-sem }()
			if p.Start != nil {
				p.Start(n)
			}
			var line func(string)
			if p.Line != nil {
				line = func(t string) { p.Line(n, t) }
			}
			err := do(n, line)
			if err != nil {
				inv.mu.Lock()
				if firstErr == nil {
					firstErr = fmt.Errorf("evaluating %s: %w", n, err)
				}
				inv.mu.Unlock()
			}
			if p.Done != nil {
				p.Done(n, err)
			}
		}(n)
	}
	wg.Wait()
	if firstErr != nil {
		return firstErr
	}
	if inv.key != "" {
		pruneCache(inv.dir, 30*24*time.Hour)
	}
	return nil
}

// Hosts returns everything loaded so far as plan types.
func (inv *Inventory) Hosts() (map[string]plan.Host, map[string]plan.Policy) {
	hosts := make(map[string]plan.Host, len(inv.facts))
	policies := make(map[string]plan.Policy, len(inv.facts))
	for name, f := range inv.facts {
		hosts[name] = plan.Host{
			Name:         name,
			Toplevel:     f.Toplevel,
			ToplevelDrv:  f.ToplevelDrv,
			System:       f.System,
			Sshable:      f.Sshable,
			HostName:     f.HostName,
			NixosVersion: f.NixosVersion,
			Kernel:       f.Kernel,
		}
		policies[name] = plan.Policy{
			Checks:     f.Checks,
			RebootLast: f.RebootLast,
		}
	}
	return hosts, policies
}

// Checks returns every check resolved so far.
func (inv *Inventory) Checks() map[string]plan.Check {
	out := make(map[string]plan.Check, len(inv.checks))
	for name, f := range inv.checks {
		out[name] = plan.Check{Name: name, DrvPath: f.Drv, OutPath: f.Out}
	}
	return out
}

// treeKey hashes everything a pure flake eval can observe: HEAD, the
// diff of tracked files against it (what nix's dirty-tree copy sees;
// untracked files are invisible to the flake), the nix version, and
// the eval expressions themselves.
func treeKey(flakePath string) (string, error) {
	head, err := exec.Command("git", "-C", flakePath, "rev-parse", "HEAD").Output()
	if err != nil {
		return "", err
	}
	diff, err := exec.Command("git", "-C", flakePath, "diff", "HEAD").Output()
	if err != nil {
		return "", err
	}
	ver, err := exec.Command("nix", "--version").Output()
	if err != nil {
		return "", err
	}
	return hashKey(string(head), string(diff), string(ver), hostExpr, checkExpr), nil
}

func hashKey(parts ...string) string {
	h := sha256.New()
	for _, p := range parts {
		h.Write([]byte(p))
		h.Write([]byte{0})
	}
	return hex.EncodeToString(h.Sum(nil))[:32]
}

func cachePath(dir, key, host string) string {
	return filepath.Join(dir, key+"-"+host+".json")
}

func checkCachePath(dir, key, name string) string {
	return filepath.Join(dir, key+"-check-"+name+".json")
}

func loadCached(dir, key, host string) (facts, bool) {
	var f facts
	if !loadJSON(cachePath(dir, key, host), &f) || f.Toplevel == "" {
		return facts{}, false
	}
	return f, true
}

func loadCachedCheck(dir, key, name string) (checkFacts, bool) {
	var f checkFacts
	if !loadJSON(checkCachePath(dir, key, name), &f) || f.Drv == "" || f.Out == "" {
		return checkFacts{}, false
	}
	return f, true
}

// storeCached is best-effort: a failed write only costs a re-eval.
func storeCached(dir, key, host string, f facts) {
	storeJSON(cachePath(dir, key, host), f)
}

func storeCachedCheck(dir, key, name string, f checkFacts) {
	storeJSON(checkCachePath(dir, key, name), f)
}

func loadJSON(path string, v any) bool {
	data, err := os.ReadFile(path)
	return err == nil && json.Unmarshal(data, v) == nil
}

func storeJSON(path string, v any) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return
	}
	data, err := json.Marshal(v)
	if err != nil {
		return
	}
	_ = os.WriteFile(path, data, 0o644)
}

// pruneCache drops entries untouched for longer than maxAge. The cache
// is disposable; failures here are ignored.
func pruneCache(dir string, maxAge time.Duration) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return
	}
	cutoff := time.Now().Add(-maxAge)
	for _, e := range entries {
		if !strings.HasSuffix(e.Name(), ".json") {
			continue
		}
		if info, err := e.Info(); err == nil && info.ModTime().Before(cutoff) {
			_ = os.Remove(filepath.Join(dir, e.Name()))
		}
	}
}

// lineWriter splits a child's stderr into lines as they arrive. Every
// line goes to fn; lines other than eval progress are kept so a
// failure can still report nix's real warnings, traces and error. It
// is installed as cmd.Stderr (exec owns the pipe and copy goroutine,
// so Output/Wait and WaitDelay keep working) rather than read through
// StderrPipe, where Wait closes the pipe under the reader, and a
// bufio.Scanner would choke on a >64 KiB trace line.
type lineWriter struct {
	fn   func(string)
	tail []byte
	kept []string
}

func (w *lineWriter) Write(p []byte) (int, error) {
	w.tail = append(w.tail, p...)
	for {
		i := bytes.IndexByte(w.tail, '\n')
		if i < 0 {
			break
		}
		w.line(string(w.tail[:i]))
		w.tail = w.tail[i+1:]
	}
	return len(p), nil
}

func (w *lineWriter) line(s string) {
	if w.fn != nil {
		w.fn(s)
	}
	if !strings.HasPrefix(s, "evaluating file ") {
		w.kept = append(w.kept, s)
	}
}

// flush emits a trailing partial line; call once the child has exited.
func (w *lineWriter) flush() {
	if len(w.tail) > 0 {
		w.line(string(w.tail))
		w.tail = nil
	}
}

// text is everything kept, as an error message.
func (w *lineWriter) text() string {
	return strings.TrimSpace(strings.Join(w.kept, "\n"))
}

// nixEval runs `nix eval --json` and returns its stdout. With line set
// the eval runs at -v, which makes nix report each file it evaluates
// on stderr (measured free: same time and memory as default verbosity)
// and streams every stderr line to it as it arrives.
func nixEval(ctx context.Context, installable string, line func(string), extra ...string) ([]byte, error) {
	args := append([]string{"eval", "--json", installable}, extra...)
	if line != nil {
		args = append(args, "-v")
	}
	cmd := exec.CommandContext(ctx, "nix", args...)
	cmd.Cancel = func() error { return cmd.Process.Signal(syscall.SIGINT) } // nix aborts cleanly on INT
	cmd.WaitDelay = 3 * time.Second                                         // then KILL
	stderr := &lineWriter{fn: line}
	cmd.Stderr = stderr
	out, err := cmd.Output()
	stderr.flush()
	if err != nil {
		if msg := stderr.text(); msg != "" {
			return nil, fmt.Errorf("%s", msg)
		}
		return nil, err
	}
	return out, nil
}

// GitInfo reports the flake repo's short revision and whether the
// working tree is dirty. Errors degrade to zero values; deploys from
// outside a git checkout are unusual but not andiamo's problem.
func GitInfo(flakePath string) (rev string, dirty bool) {
	if out, err := exec.Command("git", "-C", flakePath, "rev-parse", "--short", "HEAD").Output(); err == nil {
		rev = strings.TrimSpace(string(out))
	}
	if out, err := exec.Command("git", "-C", flakePath, "status", "--porcelain").Output(); err == nil {
		dirty = len(strings.TrimSpace(string(out))) > 0
	}
	return rev, dirty
}
