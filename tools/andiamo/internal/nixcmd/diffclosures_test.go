package nixcmd

import (
	"reflect"
	"strings"
	"testing"
)

// sample lines are verbatim from `nix store diff-closures` between two
// watson system generations (nix 2.34.8), including the ANSI coloring
// nix emits even when piped, plus one uncolored "+12.6 KiB" in the
// style its own --help shows.
var diffSample = strings.Join([]string{
	"ada: ∅ → 4.0.0, \x1b[32;1m-152.2 KiB\x1b[0m",
	"bluez-qt: +12.6 KiB",
	"discord: 1.0.153, 1.0.153-fhsenv → 1.0.154, 1.0.154-fhsenv",
	"docket: \x1b[31;1m120.2 KiB\x1b[0m",
	"electron-unwrapped: 41.9.1, 42.7.1, 43.2.0 → 42.9.3, 43.1.0, 43.4.1, \x1b[31;1m40.6 MiB\x1b[0m",
	"gstreamer: 1.28.5 → 1.28.6",
	"kdeconnect: 20.08.2 → ∅, -6597.8 KiB",
	"nixos-system-watson: 26.05.20260819.b18a4b9 → 26.05.20260827.d57af92",
	"perl5.42.3-Test-RequiresInternet: ∅ → 0.05",
}, "\n")

func TestParseDiffClosures(t *testing.T) {
	got, err := parseDiffClosures(diffSample)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	want := []PkgDiff{
		{Name: "ada", Added: []string{"4.0.0"}, SizeDelta: -155852},
		{Name: "bluez-qt", SizeDelta: 12902},
		{Name: "discord", Removed: []string{"1.0.153", "1.0.153-fhsenv"}, Added: []string{"1.0.154", "1.0.154-fhsenv"}},
		{Name: "docket", SizeDelta: 123084},
		{Name: "electron-unwrapped", Removed: []string{"41.9.1", "42.7.1", "43.2.0"}, Added: []string{"42.9.3", "43.1.0", "43.4.1"}, SizeDelta: 42572185},
		{Name: "gstreamer", Removed: []string{"1.28.5"}, Added: []string{"1.28.6"}},
		{Name: "kdeconnect", Removed: []string{"20.08.2"}, SizeDelta: -6756147},
		{Name: "nixos-system-watson", Removed: []string{"26.05.20260819.b18a4b9"}, Added: []string{"26.05.20260827.d57af92"}},
		{Name: "perl5.42.3-Test-RequiresInternet", Added: []string{"0.05"}},
	}
	if len(got) != len(want) {
		t.Fatalf("parsed %d diffs, want %d: %+v", len(got), len(want), got)
	}
	for i := range want {
		if !reflect.DeepEqual(got[i], want[i]) {
			t.Errorf("diff %d:\n got %+v\nwant %+v", i, got[i], want[i])
		}
	}
}

func TestParseDiffClosuresEmpty(t *testing.T) {
	got, err := parseDiffClosures("")
	if err != nil || got != nil {
		t.Errorf("identical closures should parse to nil, nil; got %+v, %v", got, err)
	}
}

func TestParseDiffClosuresUnrecognized(t *testing.T) {
	for _, line := range []string{
		"no separator here",
		"name: not a size",
		": 1.0 → 2.0",
	} {
		if _, err := parseDiffClosures(line); err == nil {
			t.Errorf("%q should be an error, not a silent drop", line)
		}
	}
}

func TestParseSizeDelta(t *testing.T) {
	cases := []struct {
		in   string
		want int64
		ok   bool
	}{
		{"+12.6 KiB", 12902, true},
		{"-152.2 KiB", -155852, true},
		{"40.6 MiB", 42572185, true},
		{"1.5 GiB", 1610612736, true},
		{"3 B", 3, true},
		{"1.28.6", 0, false},
		{"12 XiB", 0, false},
		{"KiB", 0, false},
	}
	for _, c := range cases {
		got, ok := parseSizeDelta(c.in)
		if got != c.want || ok != c.ok {
			t.Errorf("parseSizeDelta(%q) = %d, %v; want %d, %v", c.in, got, ok, c.want, c.ok)
		}
	}
}
