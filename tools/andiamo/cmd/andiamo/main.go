// andiamo — let's go. Small deployment CLI for this flake's fleet.
//
// Derives its host inventory from nixosConfigurations via nix eval,
// reads actual state from each host's system symlinks, and deploys in
// parallel: safe changes activate live via switch, while boot-critical
// changes are staged and rebooted per the -reboot mode (default: ask).
package main

import (
	"bufio"
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"os/signal"
	"path/filepath"
	"runtime"
	"slices"
	"sort"
	"strconv"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"

	"github.com/kylerisse/nixcfg/tools/andiamo/internal/confdiff"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/flake"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/nixcmd"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/plan"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/remote"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/ui"
)

const version = "0.1.2"

const usageText = `andiamo — let's go

Usage:
  andiamo status [HOST...] [flags]     show fleet deployment state (read-only)
  andiamo plan [HOST...] [flags]       preview deploys: actions, closure and config diffs
  andiamo deploy (HOST... | -all) [flags]   deploy hosts in parallel
  andiamo hosts [flags]                show derived inventory and policy
  andiamo version

Common flags:
  -flake PATH     flake to operate on (default ".")
  -no-color       plain output
  -timeout DUR    ssh connect timeout for probes (default 5s)
  -eval-jobs N    max concurrent nix evals (default min(cores, 8))
  -no-cache       bypass the content-keyed inventory cache

Status flags:
  -json           machine-readable output

Plan flags:
  -reboot MODE    predict actions under this mode (default ask). Plan
                  builds missing systems locally and may fetch a host's
                  running closure for the diff; hosts are not touched.

Deploy flags:
  -all            deploy every deployable host
  -reboot MODE    ask | auto | always | never (default ask). Safe changes
                  always activate live via switch; boot-critical changes
                  (kernel/initrd/kernel-modules/systemd/kernel-params)
                  are staged, then:
                  ask = offer to reboot now (non-TTY: stays staged),
                  auto = reboot without asking, never = stay staged.
                  always = boot + reboot every host regardless.
  -dry-run        build and probe, print the per-host action plan, change nothing
  -skip-checks    skip the hosts' flake check gates
  -jobs N         max concurrent host deployments (default 4)
`

type common struct {
	flakePath string
	noColor   bool
	timeout   time.Duration
	evalJobs  int
	noCache   bool
}

func addCommon(fs *flag.FlagSet) *common {
	c := &common{}
	defaultJobs := min(runtime.NumCPU(), 8)
	fs.StringVar(&c.flakePath, "flake", ".", "path to the flake")
	fs.BoolVar(&c.noColor, "no-color", false, "disable colored output")
	fs.DurationVar(&c.timeout, "timeout", 5*time.Second, "ssh connect timeout for probes")
	fs.IntVar(&c.evalJobs, "eval-jobs", defaultJobs, "max concurrent nix evals (each peaks ~1GB)")
	fs.BoolVar(&c.noCache, "no-cache", false, "bypass the inventory cache")
	return c
}

func main() {
	os.Exit(run(os.Args[1:]))
}

// parseMixed parses fs over args while allowing flags and positional
// arguments to be interleaved (stdlib flag stops at the first
// positional). Returns the positionals in order.
func parseMixed(fs *flag.FlagSet, args []string) []string {
	var positional []string
	rest := args
	for len(rest) > 0 {
		_ = fs.Parse(rest)
		rest = fs.Args()
		for len(rest) > 0 && !strings.HasPrefix(rest[0], "-") {
			positional = append(positional, rest[0])
			rest = rest[1:]
		}
	}
	return positional
}

func run(args []string) int {
	if len(args) == 0 {
		fmt.Print(usageText)
		return 2
	}
	var cmd func(context.Context, []string) int
	switch args[0] {
	case "status":
		cmd = cmdStatus
	case "plan":
		cmd = cmdPlan
	case "deploy":
		cmd = cmdDeploy
	case "hosts":
		cmd = cmdHosts
	case "version", "-version", "--version":
		fmt.Println("andiamo " + version)
		return 0
	case "help", "-h", "-help", "--help":
		fmt.Print(usageText)
		return 0
	default:
		fmt.Fprintf(os.Stderr, "andiamo: unknown command %q\n\n%s", args[0], usageText)
		return 2
	}

	// One root context for the whole command. The first SIGINT/SIGTERM
	// cancels everything — queued work bails out, running nix and ssh
	// children get SIGINT (see the spawn sites) — and restores the
	// default disposition so a second signal kills outright.
	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()
	sigs := make(chan os.Signal, 1)
	signal.Notify(sigs, os.Interrupt, syscall.SIGTERM)
	var got atomic.Value
	go func() {
		s := <-sigs
		got.Store(s)
		cancel()
		signal.Stop(sigs)
	}()

	code := cmd(ctx, args[1:])
	if s, ok := got.Load().(syscall.Signal); ok {
		fmt.Fprintf(os.Stderr, "andiamo: interrupted (%s)\n", sigName(s))
		return 128 + int(s)
	}
	return code
}

func sigName(s syscall.Signal) string {
	switch s {
	case syscall.SIGINT:
		return "SIGINT"
	case syscall.SIGTERM:
		return "SIGTERM"
	}
	return s.String()
}

// fail reports err on stderr and returns code. Once the context is
// cancelled it prints nothing: run's closing "interrupted" line is the
// only explanation the operator needs, not "context canceled" or
// "signal: interrupt" from whichever child died first.
func fail(ctx context.Context, code int, err error) int {
	if ctx.Err() == nil {
		fmt.Fprintln(os.Stderr, "andiamo:", err)
	}
	return code
}

// fleet bundles everything derived from the flake plus the identity of
// the machine andiamo runs on. hosts/policies cover only the hosts that
// were resolved for this invocation.
type fleet struct {
	inv      *flake.Inventory
	flakeDir string // absolute, for shortening eval paths
	hosts    map[string]plan.Host
	policies map[string]plan.Policy
	self     string
}

// evalProgress wires an eval Progress block: rows flip to evaluating,
// stream what nix is reading, and end evaluated / eval failed /
// interrupted.
func (f *fleet) evalProgress(ctx context.Context, prog *ui.Progress) flake.EvalProgress {
	return flake.EvalProgress{
		Start: func(n string) { prog.Set(n, "evaluating") },
		Line:  func(n, t string) { prog.Detail(n, shortEvalLine(f.flakeDir, t)) },
		Done: func(n string, err error) {
			switch {
			case err != nil && ctx.Err() != nil:
				prog.Done(n, false, "interrupted")
			case err != nil:
				prog.Done(n, false, "eval failed")
			default:
				prog.Done(n, true, "evaluated")
			}
		},
	}
}

// loadFleet resolves the requested hosts against the flake and loads
// their facts — instantly from the content-keyed cache where possible,
// otherwise via parallel per-host nix evals.
func loadFleet(ctx context.Context, c *common, args []string, all bool) (*fleet, []string, error) {
	names, err := flake.HostNames(ctx, c.flakePath)
	if err != nil {
		return nil, nil, err
	}
	sel, err := resolveNames(args, all, names)
	if err != nil {
		return nil, nil, err
	}
	f := &fleet{inv: flake.Open(c.flakePath, c.evalJobs, c.noCache)}
	f.flakeDir, _ = filepath.Abs(c.flakePath)
	f.self, _ = os.Hostname()
	have, missing := f.inv.Cached(sel)
	start := time.Now()
	if len(missing) > 0 {
		prog := ui.NewProgress(missing)
		err := f.inv.Eval(ctx, missing, f.evalProgress(ctx, prog))
		prog.Close()
		if err != nil {
			return nil, nil, err
		}
	}
	summary := fmt.Sprintf("inventory: %d cached", len(have))
	if len(missing) > 0 {
		summary += fmt.Sprintf(", %d evaluated in %.1fs", len(missing), time.Since(start).Seconds())
	}
	fmt.Fprintln(os.Stderr, ui.Dim(summary))
	f.hosts, f.policies = f.inv.Hosts()
	return f, sel, nil
}

// loadChecks resolves the named flake checks to derivations, from the
// cache where possible, otherwise via parallel evals shown as their
// own progress block.
func (f *fleet) loadChecks(ctx context.Context, names []string) (map[string]plan.Check, error) {
	_, missing := f.inv.CachedChecks(names)
	if len(missing) > 0 {
		fmt.Printf("▸ evaluating checks: %s\n", strings.Join(missing, ", "))
		prog := ui.NewProgress(missing)
		err := f.inv.EvalChecks(ctx, missing, f.evalProgress(ctx, prog))
		prog.Close()
		if err != nil {
			return nil, err
		}
	}
	return f.inv.Checks(), nil
}

// resolveNames validates positional host args (or all) against the
// flake's host list.
func resolveNames(args []string, all bool, names []string) ([]string, error) {
	if len(args) == 0 && !all {
		return nil, fmt.Errorf("name hosts explicitly or pass -all")
	}
	if all {
		return append([]string{}, names...), nil
	}
	known := make(map[string]bool, len(names))
	for _, n := range names {
		known[n] = true
	}
	seen := map[string]bool{}
	var out []string
	for _, n := range args {
		if !known[n] {
			return nil, fmt.Errorf("unknown host %q (known: %s)", n, strings.Join(names, ", "))
		}
		if !seen[n] {
			seen[n] = true
			out = append(out, n)
		}
	}
	sort.Strings(out)
	return out, nil
}

func (f *fleet) isLocal(h plan.Host) bool   { return f.self != "" && f.self == h.HostName }
func (f *fleet) reachable(h plan.Host) bool { return h.Sshable || f.isLocal(h) }

func (f *fleet) target(h plan.Host, timeout time.Duration) remote.Target {
	return remote.Target{Host: h.Name, Local: f.isLocal(h), Timeout: timeout}
}

func printBanner(c *common) {
	rev, dirty := flake.GitInfo(c.flakePath)
	if rev == "" {
		return
	}
	if dirty {
		fmt.Printf("flake @ %s %s\n", rev, ui.Yellow("(includes uncommitted changes)"))
	} else {
		fmt.Printf("flake @ %s\n", rev)
	}
}

// probeAll probes the given hosts concurrently. Unreachable-by-design
// hosts get a zero probe (classification handles them via reachable).
func (f *fleet) probeAll(ctx context.Context, names []string, timeout time.Duration) map[string]plan.Probe {
	probes := make(map[string]plan.Probe, len(names))
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 8)
	for _, n := range names {
		h := f.hosts[n]
		if !f.reachable(h) {
			continue
		}
		wg.Add(1)
		go func(n string, h plan.Host) {
			defer wg.Done()
			var p plan.Probe
			select {
			case sem <- struct{}{}:
				p = remote.Probe(ctx, f.target(h, timeout))
				<-sem
			case <-ctx.Done():
				p = plan.Probe{Err: ctx.Err()}
			}
			mu.Lock()
			probes[n] = p
			mu.Unlock()
		}(n, h)
	}
	wg.Wait()
	return probes
}

// shortEvalLine compresses one line of `nix eval -v` stderr for a
// progress row. "evaluating file '<p>'" becomes a readable <p>:
//
//	«github:nixos/nixpkgs/f4f6…?narHash=…»/nixos/modules/x.nix → nixpkgs/nixos/modules/x.nix
//	«nix-internal»/derivation-internal.nix                    → nix-internal/derivation-internal.nix
//	/nix/store/<hash>-source/nixos/modules/x.nix              → nixos/modules/x.nix (pre-lazy-trees nix)
//	<flakeDir>/modules/nix-common/default.nix                 → modules/nix-common/default.nix
//
// Anything else (warning:, trace:, copying …) passes through. Either
// way the line is scrubbed for the live display (see ui.Scrub).
func shortEvalLine(flakeDir, text string) string {
	if p, ok := strings.CutPrefix(text, "evaluating file '"); ok {
		p = strings.TrimSuffix(p, "'")
		switch {
		case strings.HasPrefix(p, "«"):
			if i := strings.Index(p, "»"); i >= 0 {
				p = flakeRefName(p[len("«"):i]) + p[i+len("»"):]
			}
		case strings.HasPrefix(p, "/nix/store/"):
			rest := p[len("/nix/store/"):]
			if i := strings.Index(rest, "-source/"); i >= 0 {
				p = rest[i+len("-source/"):]
			}
		case flakeDir != "" && strings.HasPrefix(p, flakeDir+"/"):
			p = p[len(flakeDir)+1:]
		}
		text = p
	}
	return ui.Scrub(text)
}

// flakeRefName reduces a flake reference as nix prints it inside «»
// to a short name: the repo for forge refs (github:owner/repo/rev →
// repo), the last path element otherwise, and internal sources
// (nix-internal, flakes-internal) unchanged.
func flakeRefName(ref string) string {
	if i := strings.IndexByte(ref, '?'); i >= 0 {
		ref = ref[:i]
	}
	scheme, rest, ok := strings.Cut(ref, ":")
	if !ok {
		return ref
	}
	parts := strings.Split(strings.Trim(rest, "/"), "/")
	switch scheme {
	case "github", "gitlab", "sourcehut":
		if len(parts) >= 2 {
			return parts[1]
		}
	}
	return parts[len(parts)-1]
}

func pad(s string, w int) string {
	if len(s) >= w {
		return s
	}
	return s + strings.Repeat(" ", w-len(s))
}

// stateCells returns the coloured glyph and label for a state.
func stateCells(s plan.State) (glyph, label string) {
	l := plan.Label(s)
	switch s {
	case plan.InSync:
		return ui.Green("✓"), ui.Green(l)
	case plan.RebootPending, plan.Staged, plan.OutOfDate:
		return ui.Yellow("↻"), ui.Yellow(l)
	case plan.Unreachable:
		return ui.Red("~"), ui.Red(l)
	case plan.LocalOnly:
		return ui.Dim("⌂"), ui.Dim(l)
	}
	return "?", l
}

// factHeader and factCells are the per-host columns shared by status
// and the deploy dry run: what the host runs now, with "→ expected"
// where the flake says otherwise. SYSTEM is the toplevel store hash —
// the thing the state is actually decided on — so a row is never
// "out of date" without showing what differs, even when no other
// column moved. A host that wasn't probed gets dashes throughout.
var factHeader = []string{"GEN", "UP", "KERNEL", "NIXOS", "SYSTEM"}

func factCells(h plan.Host, p plan.Probe, probed bool) []string {
	if !probed || p.Err != nil {
		return []string{"-", "-", "-", "-", "-"}
	}
	gen := "-"
	if p.Generation > 0 {
		gen = strconv.Itoa(p.Generation)
	}
	return []string{
		gen,
		plan.Uptime(p.UptimeSec),
		plan.Arrow(p.Kernel, h.Kernel),
		plan.Arrow(p.NixosVersion, h.NixosVersion),
		plan.Arrow(ui.ShortPath(p.Current), ui.ShortPath(h.Toplevel)),
	}
}

func dimAll(cells []string) []string {
	out := make([]string, len(cells))
	for i, c := range cells {
		out[i] = ui.Dim(c)
	}
	return out
}

// ---------------------------------------------------------------- status

func cmdStatus(ctx context.Context, args []string) int {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	c := addCommon(fs)
	jsonOut := fs.Bool("json", false, "machine-readable output")
	hostArgs := parseMixed(fs, args)
	ui.Init(c.noColor)

	f, selected, err := loadFleet(ctx, c, hostArgs, len(hostArgs) == 0)
	if err != nil {
		return fail(ctx, 2, err)
	}
	probes := f.probeAll(ctx, selected, c.timeout)
	if ctx.Err() != nil {
		return fail(ctx, 2, ctx.Err())
	}

	type rowT struct {
		name  string
		state plan.State
		probe plan.Probe
	}
	rows := make([]rowT, 0, len(selected))
	exit := 0
	for _, n := range selected {
		h := f.hosts[n]
		st := plan.Classify(h.Toplevel, f.reachable(h), probes[n])
		switch st {
		case plan.Unreachable:
			exit = 2
		case plan.OutOfDate, plan.Staged, plan.RebootPending:
			if exit < 1 {
				exit = 1
			}
		}
		rows = append(rows, rowT{n, st, probes[n]})
	}

	if *jsonOut {
		type jsonRow struct {
			Host                 string `json:"host"`
			State                string `json:"state"`
			Expected             string `json:"expected"`
			Current              string `json:"current,omitempty"`
			Booted               string `json:"booted,omitempty"`
			Profile              string `json:"profile,omitempty"`
			Generation           int    `json:"generation,omitempty"`
			DeployedAt           string `json:"deployedAt,omitempty"`
			UptimeSec            int64  `json:"uptimeSec,omitempty"`
			Kernel               string `json:"kernel,omitempty"`
			ExpectedKernel       string `json:"expectedKernel,omitempty"`
			NixosVersion         string `json:"nixosVersion,omitempty"`
			ExpectedNixosVersion string `json:"expectedNixosVersion,omitempty"`
			Error                string `json:"error,omitempty"`
		}
		out := make([]jsonRow, 0, len(rows))
		for _, r := range rows {
			h := f.hosts[r.name]
			jr := jsonRow{
				Host:                 r.name,
				State:                string(r.state),
				Expected:             h.Toplevel,
				Current:              r.probe.Current,
				Booted:               r.probe.Booted,
				Profile:              r.probe.Profile,
				Generation:           r.probe.Generation,
				UptimeSec:            r.probe.UptimeSec,
				Kernel:               r.probe.Kernel,
				ExpectedKernel:       h.Kernel,
				NixosVersion:         r.probe.NixosVersion,
				ExpectedNixosVersion: h.NixosVersion,
			}
			if r.probe.DeployedAt > 0 {
				jr.DeployedAt = time.Unix(r.probe.DeployedAt, 0).Format(time.RFC3339)
			}
			if r.probe.Err != nil {
				jr.Error = r.probe.Err.Error()
			}
			out = append(out, jr)
		}
		enc := json.NewEncoder(os.Stdout)
		enc.SetIndent("", "  ")
		_ = enc.Encode(out)
		return exit
	}

	printBanner(c)
	table := [][]string{dimAll(append([]string{"", "HOST", "STATE"}, factHeader...))}
	for _, r := range rows {
		h := f.hosts[r.name]
		glyph, label := stateCells(r.state)
		detail := plan.Detail(r.state, r.probe.Err)
		if r.state == plan.LocalOnly {
			detail = ui.Dim(detail)
		}
		cells := append([]string{glyph, r.name, label}, factCells(h, r.probe, f.reachable(h))...)
		table = append(table, append(cells, detail))
	}
	fmt.Print(ui.Table(table))
	return exit
}

// ---------------------------------------------------------------- plan

// hostPlanT is the per-host outcome of planning: what deploy will do,
// or why the host is skipped.
type hostPlanT struct {
	name       string
	mode       string // switch | boot
	doReboot   bool
	skipInSync bool
	probeErr   error
}

// classifyPlans sorts probed hosts into skipped (probe failed, already
// in sync) and toDeploy. Every name must have been probed.
func classifyPlans(f *fleet, names []string, probes map[string]plan.Probe) (map[string]hostPlanT, []string) {
	plans := make(map[string]hostPlanT, len(names))
	var toDeploy []string
	for _, n := range names {
		h := f.hosts[n]
		p := probes[n]
		hp := hostPlanT{name: n}
		switch {
		case p.Err != nil:
			hp.probeErr = p.Err
		case plan.Classify(h.Toplevel, true, p) == plan.InSync:
			hp.skipInSync = true
		default:
			toDeploy = append(toDeploy, n)
		}
		plans[n] = hp
	}
	return plans, toDeploy
}

// decideModes fills in switch vs boot(+reboot) for the hosts getting a
// deployment. The toplevels must already exist in the local store —
// the reboot call reads their boot-critical links.
func decideModes(f *fleet, toDeploy []string, probes map[string]plan.Probe, plans map[string]hostPlanT, rebootMode string) {
	for _, n := range toDeploy {
		h := f.hosts[n]
		hp := plans[n]
		needs := plan.NeedsReboot(remote.LocalLinks(h.Toplevel), probes[n].BootedLinks)
		switch rebootMode {
		case "always":
			hp.mode, hp.doReboot = "boot", true
		default: // ask, auto, never
			if needs {
				hp.mode = "boot"
				hp.doReboot = rebootMode == "auto"
			} else {
				hp.mode = "switch"
			}
		}
		if f.isLocal(h) {
			hp.doReboot = false // never reboot the machine andiamo runs on
		}
		plans[n] = hp
	}
}

// actionLabel describes what deploy will do for a planned host, shared
// by the plan command and the deploy dry run.
func actionLabel(hp hostPlanT, local bool, rebootMode string) string {
	switch {
	case hp.probeErr != nil:
		return "-"
	case hp.skipInSync:
		return ui.Dim("nothing to do")
	case hp.mode == "switch":
		return ui.Green("switch (no reboot)")
	case hp.doReboot:
		return ui.Yellow("boot + reboot + verify")
	case local:
		return ui.Yellow("boot, then reboot this machine yourself")
	case rebootMode == "ask":
		return ui.Yellow("boot, then prompt to reboot")
	default:
		return ui.Yellow("boot (reboot left to you)")
	}
}

func cmdPlan(ctx context.Context, args []string) int {
	fs := flag.NewFlagSet("plan", flag.ExitOnError)
	c := addCommon(fs)
	rebootMode := fs.String("reboot", "ask", "ask | auto | always | never")
	hostArgs := parseMixed(fs, args)
	ui.Init(c.noColor)

	switch *rebootMode {
	case "ask", "auto", "always", "never":
	default:
		fmt.Fprintf(os.Stderr, "andiamo: -reboot must be ask, auto, always, or never\n")
		return 2
	}

	f, selected, err := loadFleet(ctx, c, hostArgs, len(hostArgs) == 0)
	if err != nil {
		return fail(ctx, 2, err)
	}
	printBanner(c)

	var probed []string
	for _, n := range selected {
		if f.reachable(f.hosts[n]) {
			probed = append(probed, n)
		}
	}
	fmt.Printf("▸ probing %d host(s)\n", len(probed))
	probes := f.probeAll(ctx, probed, c.timeout)
	if ctx.Err() != nil {
		return fail(ctx, 2, ctx.Err())
	}
	plans, toDeploy := classifyPlans(f, probed, probes)

	if len(toDeploy) > 0 {
		if checks := plan.Checks(toDeploy, f.policies); len(checks) > 0 {
			fmt.Printf("deploy would gate on checks: %s\n", strings.Join(checks, ", "))
		}
		// The new systems must exist locally: the switch-vs-boot call
		// reads their boot-critical links, the diff their closures.
		fmt.Printf("▸ building %d system(s)\n", len(toDeploy))
		rows := make(map[string]buildRow, len(toDeploy))
		for _, n := range toDeploy {
			rows[n] = buildRow{drv: f.hosts[n].ToplevelDrv, out: f.hosts[n].Toplevel}
		}
		outs, err := buildRows(ctx, toDeploy, rows)
		if err != nil {
			return fail(ctx, 1, err)
		}
		for i, n := range toDeploy {
			if outs[i] != f.hosts[n].Toplevel {
				return fail(ctx, 1, fmt.Errorf("%s: built %s but eval expected %s", n, outs[i], f.hosts[n].Toplevel))
			}
		}
		decideModes(f, toDeploy, probes, plans, *rebootMode)
	}

	// Action table: the deploy waves, then hosts plan can only observe.
	normal, last := plan.Partition(probed, f.policies)
	fmt.Println("\nplanned actions:")
	table := [][]string{dimAll(append([]string{"", "HOST", "STATE", "ACTION"}, factHeader...))}
	addWave := func(names []string, tag string) {
		for _, n := range names {
			h := f.hosts[n]
			hp := plans[n]
			st := plan.Classify(h.Toplevel, true, probes[n])
			glyph, label := stateCells(st)
			detail := tag
			if hp.probeErr != nil {
				detail = hp.probeErr.Error()
			}
			cells := append([]string{glyph, n, label, actionLabel(hp, f.isLocal(h), *rebootMode)}, factCells(h, probes[n], true)...)
			table = append(table, append(cells, detail))
		}
	}
	addWave(normal, "")
	addWave(last, ui.Dim("reboot-last wave"))
	for _, n := range selected {
		if f.reachable(f.hosts[n]) {
			continue
		}
		glyph, label := stateCells(plan.LocalOnly)
		cells := append([]string{glyph, n, label, ui.Dim("-")}, factCells(f.hosts[n], plan.Probe{}, false)...)
		table = append(table, append(cells, ui.Dim(plan.Detail(plan.LocalOnly, nil))))
	}
	fmt.Print(ui.Table(table))

	if len(toDeploy) > 0 && ctx.Err() == nil {
		fmt.Printf("\n▸ computing closure diffs\n")
		hds := diffAll(ctx, f, toDeploy, probes)
		dNormal, dLast := plan.Partition(toDeploy, f.policies)
		for _, n := range append(append([]string{}, dNormal...), dLast...) {
			printHostDiff(n, hds[n])
		}
	}
	if ctx.Err() != nil {
		return fail(ctx, 2, ctx.Err())
	}

	exit := 0
	for _, n := range probed {
		switch plan.Classify(f.hosts[n].Toplevel, true, probes[n]) {
		case plan.Unreachable:
			exit = 2
		case plan.OutOfDate, plan.Staged, plan.RebootPending:
			if exit < 1 {
				exit = 1
			}
		}
	}
	return exit
}

// hostDiff is one host's closure and config diff, or the reason there
// isn't one.
type hostDiff struct {
	diffs      []nixcmd.PkgDiff
	conf       []confdiff.Change
	confNote   string // when only the config diff failed
	cmdAdded   []string
	cmdRemoved []string
	note       string // when no diff could be produced at all
}

// diffAll computes running→expected closure diffs for the hosts about
// to be deployed. Old closures usually still exist locally (this
// machine built them once); one that doesn't (GC'd, or deployed from
// elsewhere) is fetched back from its host first.
func diffAll(ctx context.Context, f *fleet, names []string, probes map[string]plan.Probe) map[string]hostDiff {
	out := make(map[string]hostDiff, len(names))
	var mu sync.Mutex
	var wg sync.WaitGroup
	sem := make(chan struct{}, 4)
	prog := ui.NewProgress(names)
	for _, n := range names {
		wg.Add(1)
		go func(n string) {
			defer wg.Done()
			var hd hostDiff
			select {
			case sem <- struct{}{}:
				hd = diffHost(ctx, f, n, probes[n].Current, prog)
				<-sem
			case <-ctx.Done():
				prog.Done(n, false, "interrupted")
				hd.note = "interrupted"
			}
			mu.Lock()
			out[n] = hd
			mu.Unlock()
		}(n)
	}
	wg.Wait()
	prog.Close()
	return out
}

func diffHost(ctx context.Context, f *fleet, n, old string, prog *ui.Progress) hostDiff {
	h := f.hosts[n]
	interrupted := func() hostDiff {
		prog.Done(n, false, "interrupted")
		return hostDiff{note: "interrupted"}
	}
	if old == "" {
		prog.Done(n, true, "no running system to diff against")
		return hostDiff{note: "running system unknown — nothing to diff against"}
	}
	if old == h.Toplevel {
		prog.Done(n, true, "same system, reboot only")
		return hostDiff{note: "target system already active — only the reboot is pending"}
	}
	if _, err := os.Stat(old); err != nil {
		if f.isLocal(h) {
			prog.Done(n, false, "running system missing from store")
			return hostDiff{note: "closure diff unavailable: running system missing from the local store"}
		}
		prog.Set(n, "fetching running system from host")
		if err := nixcmd.CopyFrom(ctx, h.Name, old); err != nil {
			if ctx.Err() != nil {
				return interrupted()
			}
			prog.Done(n, false, "fetch failed")
			return hostDiff{note: "closure diff unavailable: " + err.Error()}
		}
	}
	prog.Set(n, "diffing closures")
	diffs, err := nixcmd.DiffClosures(ctx, old, h.Toplevel)
	if err != nil {
		if ctx.Err() != nil {
			return interrupted()
		}
		prog.Done(n, false, "diff failed")
		return hostDiff{note: "closure diff unavailable: " + err.Error()}
	}
	hd := hostDiff{diffs: diffs}
	// Config diff over the same pair: what changes in the rendered
	// /etc and on the system path. This is what catches changes the
	// closure cannot show, like a systemPackages entry whose store
	// path some package already carried.
	prog.Set(n, "diffing config")
	conf, err := confdiff.Etc(ctx, old, h.Toplevel)
	if err != nil {
		if ctx.Err() != nil {
			return interrupted()
		}
		hd.confNote = "config diff unavailable: " + err.Error()
	} else {
		hd.conf = conf
	}
	if added, removed, err := confdiff.Commands(old, h.Toplevel); err == nil {
		hd.cmdAdded, hd.cmdRemoved = added, removed
	}
	summary := summarizeDiffs(diffs).oneLine()
	if len(hd.conf) > 0 {
		summary += fmt.Sprintf(" · %d config file(s)", len(hd.conf))
	}
	prog.Done(n, true, summary)
	return hd
}

// diffSummary tallies a closure diff. added/removed count packages
// that only gained or only lost versions (which per PkgDiff need not
// mean the package itself appeared or vanished); rebuilt counts
// packages whose contents changed without any version change.
type diffSummary struct {
	changed, added, removed int
	rebuilt                 int
	rebuiltDelta            int64
	net                     int64
}

func summarizeDiffs(diffs []nixcmd.PkgDiff) diffSummary {
	var s diffSummary
	for _, d := range diffs {
		s.net += d.SizeDelta
		switch {
		case d.Removed == nil && d.Added == nil:
			s.rebuilt++
			s.rebuiltDelta += d.SizeDelta
		case d.Removed == nil:
			s.added++
		case d.Added == nil:
			s.removed++
		default:
			s.changed++
		}
	}
	return s
}

func (s diffSummary) oneLine() string {
	var parts []string
	count := func(n int, word string) {
		if n > 0 {
			parts = append(parts, fmt.Sprintf("%d %s", n, word))
		}
	}
	count(s.changed, "changed")
	if s.added > 0 {
		parts = append(parts, versionCount(s.added, "added"))
	}
	if s.removed > 0 {
		parts = append(parts, versionCount(s.removed, "removed"))
	}
	count(s.rebuilt, "rebuilt")
	if len(parts) == 0 {
		return "no package changes"
	}
	if s.net != 0 {
		parts = append(parts, "net "+humanDelta(s.net))
	}
	return strings.Join(parts, " · ")
}

// versionCount says "N versions added/removed" rather than "N added":
// a package under "versions added" may be brand new to the closure or
// just gaining a second version next to one it keeps (see PkgDiff).
func versionCount(n int, what string) string {
	if n == 1 {
		return "1 version " + what
	}
	return fmt.Sprintf("%d versions %s", n, what)
}

// printHostDiff renders one host's section: added/removed/version
// changes as rows, content-only rebuilds collapsed into one line.
func printHostDiff(name string, hd hostDiff) {
	if hd.note != "" {
		fmt.Printf("\n%s — %s\n", name, hd.note)
		return
	}
	s := summarizeDiffs(hd.diffs)
	fmt.Printf("\n%s — %s\n", name, s.oneLine())
	var table [][]string
	for _, d := range hd.diffs {
		if d.Removed == nil && d.Added == nil {
			continue
		}
		// Green: only gained versions; red: only lost them. Version
		// changes stay plain — the arrow says it all.
		pkg := d.Name
		switch {
		case d.Removed == nil:
			pkg = ui.Green(pkg)
		case d.Added == nil:
			pkg = ui.Red(pkg)
		}
		table = append(table, []string{"  " + pkg, versionsCell(d), deltaCell(d.SizeDelta)})
	}
	if len(table) > 0 {
		fmt.Print(ui.Table(table))
	}
	if s.rebuilt > 0 {
		fmt.Println(ui.Dim(fmt.Sprintf("  %d package(s) rebuilt without a version change (net %s)", s.rebuilt, humanDelta(s.rebuiltDelta))))
	}
	if len(hd.cmdAdded)+len(hd.cmdRemoved) > 0 {
		var parts []string
		for _, c := range hd.cmdAdded {
			parts = append(parts, ui.Green("+"+c))
		}
		for _, c := range hd.cmdRemoved {
			parts = append(parts, ui.Red("-"+c))
		}
		fmt.Println("  commands: " + strings.Join(parts, " "))
	}
	if hd.confNote != "" {
		fmt.Println("  " + hd.confNote)
	}
	for _, ch := range hd.conf {
		switch ch.Kind {
		case confdiff.Added:
			fmt.Println("  " + ui.Green("A") + " " + ch.Path)
		case confdiff.Removed:
			fmt.Println("  " + ui.Red("D") + " " + ch.Path)
		case confdiff.Changed:
			fmt.Println("  " + ui.Yellow("M") + " " + ch.Path)
			printDiffLines(ch.Diff)
		}
	}
}

// maxDiffLines caps one config file's rendered diff; the full change
// is always a `diff -u` on the two toplevels away.
const maxDiffLines = 30

func printDiffLines(lines []string) {
	shown := lines
	if len(shown) > maxDiffLines {
		shown = shown[:maxDiffLines]
	}
	for _, l := range shown {
		l = ui.Scrub(l) // config contents can embed their own ANSI (etc/issue)
		switch {
		case strings.HasPrefix(l, "+"):
			l = ui.Green(l)
		case strings.HasPrefix(l, "-"):
			l = ui.Red(l)
		case strings.HasPrefix(l, "@@"):
			l = ui.Dim(l)
		}
		fmt.Println("      " + l)
	}
	if n := len(lines) - len(shown); n > 0 {
		fmt.Println(ui.Dim(fmt.Sprintf("      … %d more line(s)", n)))
	}
}

// versionsCell renders the version-set delta exactly as nix prints
// it: versions dropped → versions gained, ∅ for none.
func versionsCell(d nixcmd.PkgDiff) string {
	join := func(v []string) string {
		if len(v) == 0 {
			return "∅"
		}
		return strings.Join(v, ", ")
	}
	return join(d.Removed) + " → " + join(d.Added)
}

// deltaCell colors a size delta the way nix does: growth red,
// shrinkage green, zero omitted.
func deltaCell(n int64) string {
	switch {
	case n == 0:
		return ""
	case n > 0:
		return ui.Red(humanDelta(n))
	default:
		return ui.Green(humanDelta(n))
	}
}

// humanDelta renders a signed byte count in the binary units
// diff-closures itself uses.
func humanDelta(n int64) string {
	sign, v := "+", float64(n)
	if n < 0 {
		sign, v = "-", -v
	}
	switch {
	case v >= 1<<30:
		return fmt.Sprintf("%s%.1f GiB", sign, v/(1<<30))
	case v >= 1<<20:
		return fmt.Sprintf("%s%.1f MiB", sign, v/(1<<20))
	case v >= 1<<10:
		return fmt.Sprintf("%s%.1f KiB", sign, v/(1<<10))
	default:
		return fmt.Sprintf("%s%.0f B", sign, v)
	}
}

// ---------------------------------------------------------------- hosts

func cmdHosts(ctx context.Context, args []string) int {
	fs := flag.NewFlagSet("hosts", flag.ExitOnError)
	c := addCommon(fs)
	_ = fs.Parse(args)
	ui.Init(c.noColor)

	f, selected, err := loadFleet(ctx, c, nil, true)
	if err != nil {
		return fail(ctx, 2, err)
	}
	printBanner(c)
	fmt.Printf("%s  %s  %s  %s  %s\n",
		pad("HOST", 8), pad("SYSTEM", 14), pad("ACCESS", 10), pad("EXPECTED", 8), "POLICY")
	for _, n := range selected {
		h := f.hosts[n]
		pol := f.policies[n]
		access := "ssh"
		if f.isLocal(h) {
			access = "local"
		} else if !h.Sshable {
			access = "none"
		}
		var notes []string
		if len(pol.Checks) > 0 {
			notes = append(notes, "checks="+strings.Join(pol.Checks, ","))
		}
		if pol.RebootLast {
			notes = append(notes, "reboot-last")
		}
		if len(notes) == 0 {
			notes = append(notes, "-")
		}
		fmt.Printf("%s  %s  %s  %s  %s\n",
			pad(n, 8), pad(h.System, 14), pad(access, 10),
			pad(ui.ShortPath(h.Toplevel), 8), strings.Join(notes, " "))
	}
	return 0
}

// ---------------------------------------------------------------- deploy

type deployResult struct {
	host   string
	action string
	ok     bool
	staged bool
	msg    string
}

func cmdDeploy(ctx context.Context, args []string) int {
	fs := flag.NewFlagSet("deploy", flag.ExitOnError)
	c := addCommon(fs)
	all := fs.Bool("all", false, "deploy every deployable host")
	rebootMode := fs.String("reboot", "ask", "ask | auto | always | never")
	dryRun := fs.Bool("dry-run", false, "print the action plan, change nothing")
	skipChecks := fs.Bool("skip-checks", false, "skip flake check gates")
	jobs := fs.Int("jobs", 4, "max concurrent host deployments")
	hostArgs := parseMixed(fs, args)
	ui.Init(c.noColor)

	switch *rebootMode {
	case "ask", "auto", "always", "never":
	default:
		fmt.Fprintf(os.Stderr, "andiamo: -reboot must be ask, auto, always, or never\n")
		return 2
	}
	if *jobs < 1 {
		*jobs = 1
	}

	explicit := len(hostArgs) > 0
	f, sel, err := loadFleet(ctx, c, hostArgs, *all)
	if err != nil {
		return fail(ctx, 2, err)
	}
	// Enforce reachability: explicitly named unreachable hosts are an
	// error; -all silently excludes them.
	var selected []string
	for _, n := range sel {
		if f.reachable(f.hosts[n]) {
			selected = append(selected, n)
		} else if explicit {
			fmt.Fprintf(os.Stderr, "andiamo: %s has no ssh server and is not this machine — run andiamo there instead\n", n)
			return 2
		}
	}
	if len(selected) == 0 {
		fmt.Fprintln(os.Stderr, "andiamo: nothing to deploy")
		return 2
	}
	printBanner(c)

	// Probe first: hosts already in sync need no checks and no build.
	fmt.Printf("▸ probing %d host(s)\n", len(selected))
	probes := f.probeAll(ctx, selected, c.timeout)
	if ctx.Err() != nil {
		return fail(ctx, 2, ctx.Err())
	}

	plans, toDeploy := classifyPlans(f, selected, probes)

	if len(toDeploy) > 0 {
		// Check gates, only for hosts that actually get a deployment.
		checks := plan.Checks(toDeploy, f.policies)
		if len(checks) > 0 && !*skipChecks {
			if *dryRun {
				fmt.Printf("would gate on checks: %s\n", strings.Join(checks, ", "))
			} else {
				resolved, err := f.loadChecks(ctx, checks)
				if err != nil {
					return fail(ctx, 2, err)
				}
				fmt.Printf("▸ gating on checks: %s\n", strings.Join(checks, ", "))
				rows := make(map[string]buildRow, len(checks))
				for _, n := range checks {
					rows[n] = buildRow{drv: resolved[n].DrvPath, out: resolved[n].OutPath}
				}
				outs, err := buildRows(ctx, checks, rows)
				if err != nil {
					return fail(ctx, 1, fmt.Errorf("check gate failed: %w", err))
				}
				for i, n := range checks {
					if outs[i] != resolved[n].OutPath {
						return fail(ctx, 1, fmt.Errorf("check %s: built %s but eval expected %s", n, outs[i], resolved[n].OutPath))
					}
				}
			}
		}

		// Build all needed toplevels in one nix invocation.
		fmt.Printf("▸ building %d system(s)\n", len(toDeploy))
		rows := make(map[string]buildRow, len(toDeploy))
		for _, n := range toDeploy {
			rows[n] = buildRow{drv: f.hosts[n].ToplevelDrv, out: f.hosts[n].Toplevel}
		}
		outs, err := buildRows(ctx, toDeploy, rows)
		if err != nil {
			return fail(ctx, 1, err)
		}
		for i, n := range toDeploy {
			if outs[i] != f.hosts[n].Toplevel {
				return fail(ctx, 1, fmt.Errorf("%s: built %s but eval expected %s", n, outs[i], f.hosts[n].Toplevel))
			}
		}

		decideModes(f, toDeploy, probes, plans, *rebootMode)
	}

	normal, last := plan.Partition(selected, f.policies)

	if *dryRun {
		fmt.Println("\ndry run — planned actions:")
		table := [][]string{dimAll(append([]string{"", "HOST", "STATE", "ACTION"}, factHeader...))}
		addWave := func(names []string, tag string) {
			for _, n := range names {
				h := f.hosts[n]
				hp := plans[n]
				st := plan.Classify(h.Toplevel, true, probes[n])
				glyph, label := stateCells(st)
				action := actionLabel(hp, f.isLocal(h), *rebootMode)
				var detail string
				if hp.probeErr != nil {
					detail = hp.probeErr.Error()
				}
				if tag != "" && detail == "" {
					detail = tag
				}
				cells := append([]string{glyph, n, label, action}, factCells(h, probes[n], true)...)
				table = append(table, append(cells, detail))
			}
		}
		addWave(normal, "")
		addWave(last, ui.Dim("reboot-last wave"))
		fmt.Print(ui.Table(table))
		return 0
	}

	// Execute: normal wave, then the reboot-last wave.
	ordered := append(append([]string{}, normal...), last...)
	var toShow []string
	results := make(map[string]deployResult, len(ordered))
	for _, n := range ordered {
		hp := plans[n]
		switch {
		case hp.probeErr != nil:
			results[n] = deployResult{host: n, action: "none", ok: false, msg: "unreachable: " + hp.probeErr.Error()}
		case hp.skipInSync:
			results[n] = deployResult{host: n, action: "none", ok: true, msg: "already in sync"}
		default:
			toShow = append(toShow, n)
		}
	}

	if len(toShow) > 0 {
		fmt.Printf("▸ deploying %d host(s), %d at a time\n", len(toShow), *jobs)
		prog := ui.NewProgress(toShow)
		var mu sync.Mutex
		runWave := func(names []string) {
			var wg sync.WaitGroup
			sem := make(chan struct{}, *jobs)
			for _, n := range names {
				if _, done := results[n]; done {
					continue
				}
				wg.Add(1)
				go func(n string) {
					defer wg.Done()
					var res deployResult
					select {
					case sem <- struct{}{}:
						res = deployHost(ctx, f, f.hosts[n], plans[n].mode, plans[n].doReboot, c.timeout, prog)
						<-sem
					case <-ctx.Done():
						// Never started: no child was spawned, so this
						// host's state is exactly what the probe saw.
						prog.Done(n, false, "interrupted")
						res = deployResult{host: n, action: "none", ok: false, msg: "interrupted"}
					}
					mu.Lock()
					results[n] = res
					mu.Unlock()
				}(n)
			}
			wg.Wait()
		}
		runWave(normal)
		runWave(last)
		prog.Close()
	}

	// In ask mode, offer to finish staged hosts now. Non-TTY runs keep
	// the staged state (visible via exit code and status).
	if *rebootMode == "ask" {
		var staged []string
		for _, n := range ordered {
			r := results[n]
			if r.ok && r.staged && !f.isLocal(f.hosts[n]) {
				staged = append(staged, n)
			}
		}
		if len(staged) > 0 && ui.IsTTY(os.Stdin) && ctx.Err() == nil {
			fmt.Printf("\n%d host(s) staged awaiting reboot: %s\n", len(staged), strings.Join(staged, ", "))
			if confirm(ctx, "reboot them now?") {
				rebootStaged(ctx, f, staged, *jobs, c.timeout, results)
			}
		}
	}

	// Summary.
	fmt.Println()
	exit := 0
	for _, n := range ordered {
		r := results[n]
		mark := ui.Green("✓")
		if !r.ok {
			mark = ui.Red("✗")
			exit = 1
		} else if r.staged && exit == 0 {
			exit = 1 // visible: something still needs a reboot
		}
		fmt.Printf("%s %s  %s — %s\n", mark, pad(n, 8), pad(r.action, 14), r.msg)
	}
	return exit
}

// ---------------------------------------------------------------- build

// buildRow is one line of a build phase: the derivation to realize and
// the output whose appearance proves it done.
type buildRow struct{ drv, out string }

// buildRows realizes every row's derivation in ONE nix build — nix
// schedules shared dependencies once and the daemon serializes on its
// own locks, so one build per row would only contend — and shows what
// each row is waiting on, read from that build's internal-json log.
// An activity on a store path is shown under every row whose closure
// contains it, so a shared dependency appears under all the rows it
// blocks. A row finishes the moment its output lands in the store
// (outputs are registered atomically; this also covers substituted
// toplevels and already-passed tests). Returns the out paths in order.
func buildRows(ctx context.Context, order []string, rows map[string]buildRow) ([]string, error) {
	prog := ui.NewProgress(order)
	for _, n := range order {
		prog.Set(n, "building")
	}

	// Attribution: row → closure, queried alongside the build (under a
	// second each) and cancelled with it. A row whose query fails just
	// shows the fleet-wide totals.
	cctx, cancel := context.WithCancel(ctx)
	defer cancel()
	var memberMu sync.Mutex
	member := map[string][]string{}
	sem := make(chan struct{}, 4)
	for _, n := range order {
		go func(n string) {
			select {
			case sem <- struct{}{}:
			case <-cctx.Done():
				return
			}
			defer func() { <-sem }()
			paths, err := nixcmd.Closure(cctx, rows[n].drv)
			if err != nil {
				return
			}
			memberMu.Lock()
			defer memberMu.Unlock()
			for _, p := range paths {
				member[p] = append(member[p], n)
			}
		}(n)
	}

	var tr nixcmd.Tracker
	drvs := make([]string, len(order))
	for i, n := range order {
		drvs[i] = rows[n].drv
	}
	type result struct {
		outs []string
		err  error
	}
	done := make(chan result, 1)
	go func() {
		outs, err := nixcmd.Build(ctx, drvs, tr.Apply)
		done <- result{outs, err}
	}()

	finished := map[string]bool{}
	update := func() {
		acts := tr.Snapshot()
		totals := tr.Totals()
		memberMu.Lock()
		defer memberMu.Unlock()
		for _, n := range order {
			if finished[n] {
				continue
			}
			if _, err := os.Stat(rows[n].out); err == nil {
				prog.Done(n, true, "built")
				finished[n] = true
				continue
			}
			prog.Detail(n, buildDetail(n, acts, member, totals))
		}
	}
	tick := time.NewTicker(120 * time.Millisecond)
	defer tick.Stop()
	var res result
	for waiting := true; waiting; {
		select {
		case res = <-done:
			waiting = false
		case <-tick.C:
			update()
		}
	}
	update()
	for _, n := range order {
		if finished[n] {
			continue
		}
		if ctx.Err() != nil {
			prog.Done(n, false, "interrupted")
		} else {
			prog.Done(n, false, "build failed")
		}
	}
	prog.Close()
	return res.outs, res.err
}

// buildDetail describes what row is waiting on: its newest live
// build or fetch, else the fleet-wide counters.
func buildDetail(row string, acts []nixcmd.Activity, member map[string][]string, t nixcmd.Totals) string {
	for _, a := range acts { // newest first
		if a.Path == "" || !slices.Contains(member[a.Path], row) {
			continue
		}
		name := nixcmd.StoreName(a.Path)
		switch a.Type {
		case nixcmd.ActBuild:
			s := "building " + name
			if a.LastLine != "" {
				s += " › " + ui.Scrub(a.LastLine)
			}
			return s
		case nixcmd.ActSubstitute, nixcmd.ActCopyPath:
			s := "fetching " + name
			if a.BytesTotal > 0 {
				s += " " + nixcmd.HumanSize(a.Bytes, a.BytesTotal)
			}
			return s
		}
	}
	parts := []string{"waiting"}
	if t.BuildsExpected > 0 {
		parts = append(parts, fmt.Sprintf("%d/%d built", t.Built, t.BuildsExpected))
	}
	if t.FetchesExpected > 0 {
		parts = append(parts, fmt.Sprintf("%d/%d fetched", t.Fetched, t.FetchesExpected))
	}
	return strings.Join(parts, " · ")
}

// rebootWait allows the slow-booting pis extra time to come back.
func rebootWait(system string) time.Duration {
	if strings.HasPrefix(system, "aarch64") {
		return 10 * time.Minute
	}
	return 5 * time.Minute
}

// confirm asks a yes/no question on the terminal; anything but y/yes
// (including EOF or an interrupt while waiting) is no. The read runs
// in a goroutine so a signal at the prompt isn't swallowed by the
// blocking read; if it's abandoned it dies with the process.
func confirm(ctx context.Context, msg string) bool {
	fmt.Printf("%s [y/N] ", msg)
	answer := make(chan string, 1)
	go func() {
		line, err := bufio.NewReader(os.Stdin).ReadString('\n')
		if err != nil {
			line = ""
		}
		answer <- line
	}()
	select {
	case line := <-answer:
		line = strings.TrimSpace(strings.ToLower(line))
		return line == "y" || line == "yes"
	case <-ctx.Done():
		fmt.Println()
		return false
	}
}

// interrupted records a host whose deploy was cut short by a signal
// during step. The ssh session died mid-command, so the remote side
// may be half-done; the only honest report is "unknown".
func interrupted(prog *ui.Progress, host, action, step string) deployResult {
	prog.Done(host, false, "interrupted")
	return deployResult{host: host, action: action, ok: false,
		msg: "interrupted during " + step + " — state unknown, run andiamo status"}
}

// rebootStaged reboots hosts that were staged in ask mode, honoring
// the rebootLast partition, and updates results in place.
func rebootStaged(ctx context.Context, f *fleet, names []string, jobs int, timeout time.Duration, results map[string]deployResult) {
	normal, last := plan.Partition(names, f.policies)
	ordered := append(append([]string{}, normal...), last...)
	fmt.Printf("▸ rebooting %d host(s)\n", len(ordered))
	prog := ui.NewProgress(ordered)
	var mu sync.Mutex
	wave := func(ns []string) {
		var wg sync.WaitGroup
		sem := make(chan struct{}, jobs)
		for _, n := range ns {
			wg.Add(1)
			go func(n string) {
				defer wg.Done()
				select {
				case sem <- struct{}{}:
				case <-ctx.Done():
					// Not rebooted: the staged result already in
					// results stands.
					prog.Done(n, false, "interrupted")
					return
				}
				defer func() { <-sem }()
				h := f.hosts[n]
				t := f.target(h, timeout)
				prog.Set(n, "rebooting")
				remote.Reboot(ctx, t)
				prog.Set(n, "waiting for reboot")
				res := deployResult{host: n, action: "boot+reboot", ok: true, msg: "booted " + ui.ShortPath(h.Toplevel)}
				if err := remote.WaitForBoot(ctx, t, h.Toplevel, rebootWait(h.System)); err != nil {
					if ctx.Err() != nil {
						res = interrupted(prog, n, "boot+reboot", "reboot")
					} else {
						res.ok = false
						res.msg = err.Error()
						prog.Done(n, false, "reboot verify failed")
					}
				} else {
					prog.Done(n, true, "boot + reboot")
				}
				mu.Lock()
				results[n] = res
				mu.Unlock()
			}(n)
		}
		wg.Wait()
	}
	wave(normal)
	wave(last)
	prog.Close()
}

func deployHost(ctx context.Context, f *fleet, h plan.Host, mode string, doReboot bool, timeout time.Duration, prog *ui.Progress) deployResult {
	t := f.target(h, timeout)
	top := h.Toplevel

	if !t.Local {
		prog.Set(h.Name, "copying closure")
		if err := nixcmd.Copy(ctx, h.Name, top); err != nil {
			if ctx.Err() != nil {
				return interrupted(prog, h.Name, "copy", "copy")
			}
			prog.Done(h.Name, false, "copy failed")
			return deployResult{host: h.Name, action: "copy", ok: false, msg: err.Error()}
		}
	}

	prog.Set(h.Name, "activating ("+mode+")")
	if err := remote.Activate(ctx, t, top, mode); err != nil {
		if ctx.Err() != nil {
			return interrupted(prog, h.Name, mode, mode)
		}
		prog.Done(h.Name, false, "activation failed")
		return deployResult{host: h.Name, action: mode, ok: false, msg: err.Error()}
	}

	if mode == "switch" {
		cur, err := remote.CurrentSystem(ctx, t)
		if err != nil || cur != top {
			if ctx.Err() != nil {
				return interrupted(prog, h.Name, "switch", "verify")
			}
			prog.Done(h.Name, false, "verify failed")
			msg := "current-system did not land on the deployed toplevel"
			if err != nil {
				msg = err.Error()
			}
			return deployResult{host: h.Name, action: "switch", ok: false, msg: msg}
		}
		prog.Done(h.Name, true, "switch (no reboot)")
		return deployResult{host: h.Name, action: "switch", ok: true, msg: "activated " + ui.ShortPath(top)}
	}

	if !doReboot {
		msg := "staged " + ui.ShortPath(top) + " — reboot pending"
		if t.Local {
			msg = "staged " + ui.ShortPath(top) + " — reboot this machine to finish"
		}
		prog.Done(h.Name, true, "boot (staged)")
		return deployResult{host: h.Name, action: "boot", ok: true, staged: true, msg: msg}
	}

	prog.Set(h.Name, "rebooting")
	remote.Reboot(ctx, t)
	prog.Set(h.Name, "waiting for reboot")
	if err := remote.WaitForBoot(ctx, t, top, rebootWait(h.System)); err != nil {
		if ctx.Err() != nil {
			return interrupted(prog, h.Name, "boot+reboot", "reboot")
		}
		prog.Done(h.Name, false, "reboot verify failed")
		return deployResult{host: h.Name, action: "boot+reboot", ok: false, msg: err.Error()}
	}
	prog.Done(h.Name, true, "boot + reboot")
	return deployResult{host: h.Name, action: "boot+reboot", ok: true, msg: "booted " + ui.ShortPath(top)}
}
