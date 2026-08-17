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
	"runtime"
	"sort"
	"strings"
	"sync"
	"time"

	"github.com/kylerisse/nixcfg/tools/andiamo/internal/flake"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/nixcmd"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/plan"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/remote"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/ui"
)

const version = "0.1.0"

const usageText = `andiamo — let's go

Usage:
  andiamo status [HOST...] [flags]     show fleet deployment state (read-only)
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

Deploy flags:
  -all            deploy every deployable host
  -reboot MODE    ask | auto | always | never (default ask). Safe changes
                  always activate live via switch; boot-critical changes
                  (kernel/initrd/kernel-modules/systemd) are staged, then:
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
	switch args[0] {
	case "status":
		return cmdStatus(args[1:])
	case "deploy":
		return cmdDeploy(args[1:])
	case "hosts":
		return cmdHosts(args[1:])
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
}

// fleet bundles everything derived from the flake plus the identity of
// the machine andiamo runs on. hosts/policies cover only the hosts that
// were resolved for this invocation.
type fleet struct {
	hosts    map[string]plan.Host
	policies map[string]plan.Policy
	self     string
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
	inv := flake.Open(c.flakePath, c.evalJobs, c.noCache)
	have, missing := inv.Cached(sel)
	start := time.Now()
	if len(missing) > 0 {
		prog := ui.NewProgress(missing)
		err := inv.Eval(ctx, missing, flake.EvalProgress{
			Start: func(n string) { prog.Set(n, "evaluating") },
			Done: func(n string, err error) {
				if err != nil {
					prog.Done(n, false, "eval failed")
				} else {
					prog.Done(n, true, "evaluated")
				}
			},
		})
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
	hosts, policies := inv.Hosts()
	self, _ := os.Hostname()
	return &fleet{hosts: hosts, policies: policies, self: self}, sel, nil
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
			sem <- struct{}{}
			defer func() { <-sem }()
			p := remote.Probe(ctx, f.target(h, timeout))
			mu.Lock()
			probes[n] = p
			mu.Unlock()
		}(n, h)
	}
	wg.Wait()
	return probes
}

func pad(s string, w int) string {
	if len(s) >= w {
		return s
	}
	return s + strings.Repeat(" ", w-len(s))
}

// ---------------------------------------------------------------- status

func cmdStatus(args []string) int {
	fs := flag.NewFlagSet("status", flag.ExitOnError)
	c := addCommon(fs)
	jsonOut := fs.Bool("json", false, "machine-readable output")
	hostArgs := parseMixed(fs, args)
	ui.Init(c.noColor)
	ctx := context.Background()

	f, selected, err := loadFleet(ctx, c, hostArgs, len(hostArgs) == 0)
	if err != nil {
		fmt.Fprintln(os.Stderr, "andiamo:", err)
		return 2
	}
	probes := f.probeAll(ctx, selected, c.timeout)

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
			Host         string `json:"host"`
			State        string `json:"state"`
			Expected     string `json:"expected"`
			Current      string `json:"current,omitempty"`
			Booted       string `json:"booted,omitempty"`
			Profile      string `json:"profile,omitempty"`
			Generation   int    `json:"generation,omitempty"`
			DeployedAt   string `json:"deployedAt,omitempty"`
			NixosVersion string `json:"nixosVersion,omitempty"`
			Error        string `json:"error,omitempty"`
		}
		out := make([]jsonRow, 0, len(rows))
		for _, r := range rows {
			jr := jsonRow{
				Host:         r.name,
				State:        string(r.state),
				Expected:     f.hosts[r.name].Toplevel,
				Current:      r.probe.Current,
				Booted:       r.probe.Booted,
				Profile:      r.probe.Profile,
				Generation:   r.probe.Generation,
				NixosVersion: r.probe.NixosVersion,
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
	nameW := 0
	for _, r := range rows {
		if len(r.name) > nameW {
			nameW = len(r.name)
		}
	}
	for _, r := range rows {
		expected := f.hosts[r.name].Toplevel
		gen, age, rev := "-", "-", "-"
		if r.probe.Err == nil {
			if r.probe.Generation > 0 {
				gen = fmt.Sprintf("gen %d", r.probe.Generation)
			}
			age = ui.Age(r.probe.DeployedAt)
			if v := plan.NixpkgsRev(r.probe.NixosVersion); v != "" {
				rev = v
			}
		}
		meta := ui.Dim(fmt.Sprintf("%s  %s  %s", pad(gen, 7), pad(age, 4), pad(rev, 8)))
		var glyph, state, detail string
		switch r.state {
		case plan.InSync:
			glyph, state = ui.Green("✓"), ui.Green(pad(string(r.state), 22))
			detail = ui.ShortPath(expected)
		case plan.RebootPending:
			glyph, state = ui.Yellow("↻"), ui.Yellow(pad(string(r.state), 22))
			detail = fmt.Sprintf("reboot to finish %s → %s", ui.ShortPath(r.probe.Booted), ui.ShortPath(r.probe.Current))
		case plan.Staged:
			glyph, state = ui.Yellow("↻"), ui.Yellow(pad(string(r.state), 22))
			detail = fmt.Sprintf("staged %s, running %s", ui.ShortPath(r.probe.Profile), ui.ShortPath(r.probe.Current))
		case plan.OutOfDate:
			glyph, state = ui.Yellow("↻"), ui.Yellow(pad(string(r.state), 22))
			detail = fmt.Sprintf("running %s, expected %s", ui.ShortPath(r.probe.Profile), ui.ShortPath(expected))
		case plan.Unreachable:
			glyph, state = ui.Red("~"), ui.Red(pad(string(r.state), 22))
			detail = r.probe.Err.Error()
		case plan.LocalOnly:
			glyph, state = ui.Dim("⌂"), ui.Dim(pad(string(r.state), 22))
			detail = ui.Dim("no ssh server; run andiamo on the host itself")
		}
		fmt.Printf("%s %s  %s %s %s\n", glyph, pad(r.name, nameW), state, meta, detail)
	}
	return exit
}

// ---------------------------------------------------------------- hosts

func cmdHosts(args []string) int {
	fs := flag.NewFlagSet("hosts", flag.ExitOnError)
	c := addCommon(fs)
	_ = fs.Parse(args)
	ui.Init(c.noColor)
	ctx := context.Background()

	f, selected, err := loadFleet(ctx, c, nil, true)
	if err != nil {
		fmt.Fprintln(os.Stderr, "andiamo:", err)
		return 2
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

func cmdDeploy(args []string) int {
	fs := flag.NewFlagSet("deploy", flag.ExitOnError)
	c := addCommon(fs)
	all := fs.Bool("all", false, "deploy every deployable host")
	rebootMode := fs.String("reboot", "ask", "ask | auto | always | never")
	dryRun := fs.Bool("dry-run", false, "print the action plan, change nothing")
	skipChecks := fs.Bool("skip-checks", false, "skip flake check gates")
	jobs := fs.Int("jobs", 4, "max concurrent host deployments")
	hostArgs := parseMixed(fs, args)
	ui.Init(c.noColor)
	ctx := context.Background()

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
		fmt.Fprintln(os.Stderr, "andiamo:", err)
		return 2
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

	type hostPlanT struct {
		name       string
		mode       string // switch | boot
		doReboot   bool
		skipInSync bool
		probeErr   error
	}
	plans := make(map[string]hostPlanT, len(selected))
	var toDeploy []string
	for _, n := range selected {
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

	if len(toDeploy) > 0 {
		// Check gates, only for hosts that actually get a deployment.
		checks := plan.Checks(toDeploy, f.policies)
		if len(checks) > 0 && !*skipChecks {
			if *dryRun {
				fmt.Printf("would gate on checks: %s\n", strings.Join(checks, ", "))
			} else {
				fmt.Printf("▸ gating on checks: %s\n", strings.Join(checks, ", "))
				if err := nixcmd.BuildChecks(ctx, c.flakePath, checks, ui.Live()); err != nil {
					fmt.Fprintln(os.Stderr, "andiamo: check gate failed:", err)
					return 1
				}
			}
		}

		// Build all needed toplevels in one nix invocation.
		fmt.Printf("▸ building %d system(s)\n", len(toDeploy))
		tops, err := nixcmd.BuildToplevels(ctx, c.flakePath, toDeploy, ui.Live())
		if err != nil {
			fmt.Fprintln(os.Stderr, "andiamo:", err)
			return 1
		}
		for _, n := range toDeploy {
			if tops[n] != f.hosts[n].Toplevel {
				fmt.Fprintf(os.Stderr, "andiamo: %s: built %s but eval expected %s\n", n, tops[n], f.hosts[n].Toplevel)
				return 1
			}
		}

		// Decide switch vs boot(+reboot) per host.
		for _, n := range toDeploy {
			h := f.hosts[n]
			hp := plans[n]
			needs := plan.NeedsReboot(remote.LocalLinks(h.Toplevel), probes[n].BootedLinks)
			switch *rebootMode {
			case "always":
				hp.mode, hp.doReboot = "boot", true
			default: // ask, auto, never
				if needs {
					hp.mode = "boot"
					hp.doReboot = *rebootMode == "auto"
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

	normal, last := plan.Partition(selected, f.policies)

	if *dryRun {
		fmt.Println("\ndry run — planned actions:")
		printWave := func(names []string, tag string) {
			for _, n := range names {
				hp := plans[n]
				var action string
				switch {
				case hp.probeErr != nil:
					action = ui.Red("unreachable: " + hp.probeErr.Error())
				case hp.skipInSync:
					action = ui.Dim("nothing to do (in sync)")
				case hp.mode == "switch":
					action = ui.Green("switch (no reboot)")
				case hp.doReboot:
					action = ui.Yellow("boot + reboot + verify")
				case f.isLocal(f.hosts[n]):
					action = ui.Yellow("boot, then reboot this machine yourself")
				case *rebootMode == "ask":
					action = ui.Yellow("boot, then prompt to reboot")
				default:
					action = ui.Yellow("boot (reboot left to you)")
				}
				fmt.Printf("  %s %s%s\n", pad(n, 8), action, tag)
			}
		}
		printWave(normal, "")
		printWave(last, ui.Dim("  [reboot-last wave]"))
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
					sem <- struct{}{}
					defer func() { <-sem }()
					res := deployHost(ctx, f, f.hosts[n], plans[n].mode, plans[n].doReboot, c.timeout, prog)
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
		if len(staged) > 0 && ui.IsTTY(os.Stdin) {
			fmt.Printf("\n%d host(s) staged awaiting reboot: %s\n", len(staged), strings.Join(staged, ", "))
			if confirm("reboot them now?") {
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

// rebootWait allows the slow-booting pis extra time to come back.
func rebootWait(system string) time.Duration {
	if strings.HasPrefix(system, "aarch64") {
		return 10 * time.Minute
	}
	return 5 * time.Minute
}

// confirm asks a yes/no question on the terminal; anything but y/yes
// (including EOF) is no.
func confirm(msg string) bool {
	fmt.Printf("%s [y/N] ", msg)
	line, err := bufio.NewReader(os.Stdin).ReadString('\n')
	if err != nil {
		return false
	}
	line = strings.TrimSpace(strings.ToLower(line))
	return line == "y" || line == "yes"
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
				sem <- struct{}{}
				defer func() { <-sem }()
				h := f.hosts[n]
				t := f.target(h, timeout)
				prog.Set(n, "rebooting")
				remote.Reboot(ctx, t)
				prog.Set(n, "waiting for reboot")
				res := deployResult{host: n, action: "boot+reboot", ok: true, msg: "booted " + ui.ShortPath(h.Toplevel)}
				if err := remote.WaitForBoot(ctx, t, h.Toplevel, rebootWait(h.System)); err != nil {
					res.ok = false
					res.msg = err.Error()
					prog.Done(n, false, "reboot verify failed")
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
			prog.Done(h.Name, false, "copy failed")
			return deployResult{host: h.Name, action: "copy", ok: false, msg: err.Error()}
		}
	}

	prog.Set(h.Name, "activating ("+mode+")")
	if err := remote.Activate(ctx, t, top, mode); err != nil {
		prog.Done(h.Name, false, "activation failed")
		return deployResult{host: h.Name, action: mode, ok: false, msg: err.Error()}
	}

	if mode == "switch" {
		cur, err := remote.CurrentSystem(ctx, t)
		if err != nil || cur != top {
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
		prog.Done(h.Name, false, "reboot verify failed")
		return deployResult{host: h.Name, action: "boot+reboot", ok: false, msg: err.Error()}
	}
	prog.Done(h.Name, true, "boot + reboot")
	return deployResult{host: h.Name, action: "boot+reboot", ok: true, msg: "booted " + ui.ShortPath(top)}
}
