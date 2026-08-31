package main

import (
	"errors"
	"path/filepath"
	"testing"
	"time"

	"github.com/kylerisse/nixcfg/tools/andiamo/internal/nixcmd"
	"github.com/kylerisse/nixcfg/tools/andiamo/internal/plan"
)

func TestShortEvalLine(t *testing.T) {
	const dir = "/home/me/src/nixcfg"
	cases := []struct{ in, want string }{
		{"evaluating file '«github:nixos/nixpkgs/f4f698677b11021a8f84f452e23ae9ef2427bec3?narHash=sha256-MrkfE5hF5xx4L/0h5NyJ3xQkKVftwSuKSkFSrvlTxGY%3D»/nixos/modules/config/console.nix'",
			"nixpkgs/nixos/modules/config/console.nix"},
		{"evaluating file '«github:socallinuxexpo/scale-signs/04f81f0a?narHash=sha256-x»/flake.nix'", "scale-signs/flake.nix"},
		{"evaluating file '«nix-internal»/derivation-internal.nix'", "nix-internal/derivation-internal.nix"},
		{"evaluating file '«flakes-internal»/call-flake.nix'", "flakes-internal/call-flake.nix"},
		{"evaluating file '«path:/home/me/src/other»/default.nix'", "other/default.nix"},
		{"evaluating file '/nix/store/abc123-source/nixos/modules/config/console.nix'", "nixos/modules/config/console.nix"},
		{"evaluating file '" + dir + "/modules/nix-common/default.nix'", "modules/nix-common/default.nix"},
		{"evaluating file '" + dir + "/flake.nix'", "flake.nix"},
		{"evaluating file '" + dir + "-other/flake.nix'", dir + "-other/flake.nix"},
		{"evaluating file '<nix/fetchurl.nix>'", "<nix/fetchurl.nix>"},
		{"copying '«github:nixos/nixpkgs/f4f6»/lib' to the store", "copying '«github:nixos/nixpkgs/f4f6»/lib' to the store"},
		{"warning: Git tree '/home/me/src/nixcfg' is dirty", "warning: Git tree '/home/me/src/nixcfg' is dirty"},
		{"trace:\tindented\x1b[31m red\x1b[0m", "trace: indented red"}, // colour off in tests
	}
	for _, c := range cases {
		if got := shortEvalLine(dir, c.in); got != c.want {
			t.Errorf("shortEvalLine(%q)\n got %q\nwant %q", c.in, got, c.want)
		}
	}
}

func TestBuildDetail(t *testing.T) {
	const (
		nginxDrv = "/nix/store/150zykpi9v1hhm87yf1y1b3ail40s36w-nginx-1.27.3.drv"
		linux    = "/nix/store/wl6xbyf0k5b14izm59rfh9rvdyjh4n68-linux-7.2.0"
	)
	member := map[string][]string{nginxDrv: {"qube", "gibson"}, linux: {"pi3"}}
	acts := []nixcmd.Activity{ // newest first
		{Type: nixcmd.ActCopyPath, Path: linux, Bytes: 12_400_000, BytesTotal: 45_000_000, Seq: 3},
		{Type: nixcmd.ActBuild, Path: nginxDrv, LastLine: "gcc\t-O2 \x1bfoo.c", Seq: 2},
		{Type: nixcmd.ActQueryPathInfo, Path: linux, Seq: 1},
	}
	totals := nixcmd.Totals{Built: 3, BuildsExpected: 12, Fetched: 41, FetchesExpected: 120}
	cases := map[string]string{
		"qube":   "building nginx-1.27.3 › gcc -O2 foo.c",
		"gibson": "building nginx-1.27.3 › gcc -O2 foo.c",
		"pi3":    "fetching linux-7.2.0 12.4/45.0 MB",
		"muir":   "waiting · 3/12 built · 41/120 fetched",
	}
	for row, want := range cases {
		if got := buildDetail(row, acts, member, totals); got != want {
			t.Errorf("buildDetail(%s) = %q, want %q", row, got, want)
		}
	}
	if got := buildDetail("muir", nil, member, nixcmd.Totals{}); got != "waiting" {
		t.Errorf("empty totals = %q", got)
	}
	if got := buildDetail("pi3", []nixcmd.Activity{{Type: nixcmd.ActSubstitute, Path: linux}}, member, totals); got != "fetching linux-7.2.0" {
		t.Errorf("substitute without bytes = %q", got)
	}
}

func TestHumanDelta(t *testing.T) {
	cases := []struct {
		in   int64
		want string
	}{
		{0, "+0 B"},
		{3, "+3 B"},
		{-512, "-512 B"},
		{12902, "+12.6 KiB"},
		{-155852, "-152.2 KiB"},
		{42572185, "+40.6 MiB"},
		{-1610612736, "-1.5 GiB"},
	}
	for _, c := range cases {
		if got := humanDelta(c.in); got != c.want {
			t.Errorf("humanDelta(%d) = %q, want %q", c.in, got, c.want)
		}
	}
}

func TestSummarizeDiffs(t *testing.T) {
	diffs := []nixcmd.PkgDiff{
		{Name: "changed", Removed: []string{"1"}, Added: []string{"2"}, SizeDelta: 100},
		{Name: "added", Added: []string{"1"}, SizeDelta: 50},
		{Name: "removed", Removed: []string{"1"}, SizeDelta: -30},
		{Name: "rebuilt1", SizeDelta: 10},
		{Name: "rebuilt2", SizeDelta: -5},
	}
	s := summarizeDiffs(diffs)
	if s.changed != 1 || s.added != 1 || s.removed != 1 || s.rebuilt != 2 {
		t.Errorf("counts = %+v", s)
	}
	if s.net != 125 || s.rebuiltDelta != 5 {
		t.Errorf("deltas = net %d, rebuilt %d", s.net, s.rebuiltDelta)
	}
	if got := s.oneLine(); got != "1 changed · 1 version added · 1 version removed · 2 rebuilt · net +125 B" {
		t.Errorf("oneLine = %q", got)
	}
	if got := summarizeDiffs(nil).oneLine(); got != "no package changes" {
		t.Errorf("empty oneLine = %q", got)
	}
}

func TestVersionsCell(t *testing.T) {
	cases := []struct {
		d    nixcmd.PkgDiff
		want string
	}{
		{nixcmd.PkgDiff{Removed: []string{"1.2"}, Added: []string{"1.3"}}, "1.2 → 1.3"},
		{nixcmd.PkgDiff{Added: []string{"1.0"}}, "∅ → 1.0"},
		{nixcmd.PkgDiff{Removed: []string{"1.0", "1.0-fhs"}}, "1.0, 1.0-fhs → ∅"},
	}
	for _, c := range cases {
		if got := versionsCell(c.d); got != c.want {
			t.Errorf("versionsCell(%+v) = %q, want %q", c.d, got, c.want)
		}
	}
}

func TestVerifyAgainstPlan(t *testing.T) {
	const expected = "/nix/store/new"
	const old = "/nix/store/old"
	entry := planEntry{Toplevel: expected, Current: old, Action: "switch"}
	cases := []struct {
		name    string
		e       planEntry
		covered bool
		probe   plan.Probe
		wantErr bool
	}{
		{"not covered", planEntry{}, false, plan.Probe{Current: old}, true},
		{"expected drifted", planEntry{Toplevel: "/nix/store/other", Current: old}, true, plan.Probe{Current: old}, true},
		{"host unchanged", entry, true, plan.Probe{Current: old}, false},
		{"already applied", entry, true, plan.Probe{Current: expected}, false},
		{"host drifted", entry, true, plan.Probe{Current: "/nix/store/third"}, true},
		{"unreachable passes to the executor", entry, true, plan.Probe{Err: errors.New("timeout")}, false},
	}
	for _, c := range cases {
		err := verifyAgainstPlan(c.e, c.covered, expected, c.probe)
		if (err != nil) != c.wantErr {
			t.Errorf("%s: err = %v, wantErr %v", c.name, err, c.wantErr)
		}
	}
}

func TestPlanRecordRoundtrip(t *testing.T) {
	path := filepath.Join(t.TempDir(), "sub", "plan-x.json")
	rec := planRecord{
		CreatedAt: time.Now(),
		Hosts: map[string]planEntry{
			"qube": {Toplevel: "/nix/store/x", Current: "/nix/store/y", Action: "switch", Changes: "2 changed"},
		},
	}
	savePlanRecord(path, rec)
	got, ok := loadPlanRecord(path)
	if !ok || got.Hosts["qube"] != rec.Hosts["qube"] {
		t.Errorf("roundtrip = %+v, %v", got, ok)
	}
	if _, ok := loadPlanRecord(filepath.Join(t.TempDir(), "missing.json")); ok {
		t.Error("missing file must not load")
	}
	empty := filepath.Join(t.TempDir(), "empty.json")
	savePlanRecord(empty, planRecord{CreatedAt: time.Now()})
	if _, ok := loadPlanRecord(empty); ok {
		t.Error("a record with no hosts must not gate an apply open")
	}
}
