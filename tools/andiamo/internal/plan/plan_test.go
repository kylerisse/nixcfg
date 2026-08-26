package plan

import (
	"errors"
	"reflect"
	"testing"
)

var (
	linksA = Links{Kernel: "/nix/store/aaa-linux", Initrd: "/nix/store/aaa-initrd", KernelModules: "/nix/store/aaa-mods", Systemd: "/nix/store/aaa-systemd"}
	linksB = Links{Kernel: "/nix/store/bbb-linux", Initrd: "/nix/store/aaa-initrd", KernelModules: "/nix/store/aaa-mods", Systemd: "/nix/store/aaa-systemd"}
)

func TestNeedsReboot(t *testing.T) {
	cases := []struct {
		name         string
		next, booted Links
		want         bool
	}{
		{"identical", linksA, linksA, false},
		{"kernel differs", linksB, linksA, true},
		{"initrd differs", Links{linksA.Kernel, "/nix/store/other", linksA.KernelModules, linksA.Systemd}, linksA, true},
		{"modules differ", Links{linksA.Kernel, linksA.Initrd, "/nix/store/other", linksA.Systemd}, linksA, true},
		{"systemd differs", Links{linksA.Kernel, linksA.Initrd, linksA.KernelModules, "/nix/store/other"}, linksA, true},
		{"next unresolved fails safe", Links{}, linksA, true},
		{"booted unresolved fails safe", linksA, Links{Kernel: "/nix/store/aaa-linux"}, true},
	}
	for _, c := range cases {
		if got := NeedsReboot(c.next, c.booted); got != c.want {
			t.Errorf("%s: NeedsReboot = %v, want %v", c.name, got, c.want)
		}
	}
}

func TestClassify(t *testing.T) {
	const expected = "/nix/store/new-toplevel"
	const old = "/nix/store/old-toplevel"

	cases := []struct {
		name      string
		reachable bool
		probe     Probe
		want      State
	}{
		{"not reachable", false, Probe{}, LocalOnly},
		{"ssh failed", true, Probe{Err: errors.New("timeout")}, Unreachable},
		{"all aligned", true, Probe{Current: expected, Booted: expected, Profile: expected}, InSync},
		{"profile behind", true, Probe{Current: old, Booted: old, Profile: old}, OutOfDate},
		{"profile ahead of everything else", true, Probe{Current: old, Booted: old, Profile: expected}, Staged},
		{"activated, old boot, no boot-critical change", true,
			Probe{Current: expected, Booted: old, Profile: expected, CurrentLinks: linksA, BootedLinks: linksA}, InSync},
		{"activated, old boot, kernel changed", true,
			Probe{Current: expected, Booted: old, Profile: expected, CurrentLinks: linksB, BootedLinks: linksA}, RebootPending},
		{"activated, old boot, links unknown fails safe", true,
			Probe{Current: expected, Booted: old, Profile: expected}, RebootPending},
	}
	for _, c := range cases {
		if got := Classify(expected, c.reachable, c.probe); got != c.want {
			t.Errorf("%s: Classify = %q, want %q", c.name, got, c.want)
		}
	}
}

func TestParseGeneration(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"system-143-link", 143},
		{"/nix/var/nix/profiles/system-7-link", 7},
		{"system--link", 0},
		{"system-abc-link", 0},
		{"other-143-link", 0},
		{"", 0},
	}
	for _, c := range cases {
		if got := ParseGeneration(c.in); got != c.want {
			t.Errorf("ParseGeneration(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

func TestLabelDetail(t *testing.T) {
	labels := map[State]string{
		InSync: "in sync", RebootPending: "reboot pending", Staged: "staged",
		OutOfDate: "out of date", Unreachable: "unreachable", LocalOnly: "local only",
	}
	for s, want := range labels {
		if got := Label(s); got != want {
			t.Errorf("Label(%q) = %q, want %q", s, got, want)
		}
	}
	if Detail(InSync, nil) != "" || Detail(OutOfDate, nil) != "" {
		t.Error("in sync / out of date need no detail")
	}
	if d := Detail(Unreachable, errors.New("ssh: connect timeout")); d != "ssh: connect timeout" {
		t.Errorf("Detail(Unreachable) = %q", d)
	}
	if Detail(Staged, nil) == "" || Detail(RebootPending, nil) == "" || Detail(LocalOnly, nil) == "" {
		t.Error("half-deployed and local-only states need a detail")
	}
}

func TestArrow(t *testing.T) {
	cases := []struct {
		running, expected, want string
	}{
		{"6.18.46", "6.18.46", "6.18.46"},
		{"6.18.46", "7.2", "6.18.46 → 7.2"},
		{"", "a61d215", "- → a61d215"},
		{"a61d215", "", "a61d215"},
		{"", "", "-"},
	}
	for _, c := range cases {
		if got := Arrow(c.running, c.expected); got != c.want {
			t.Errorf("Arrow(%q, %q) = %q, want %q", c.running, c.expected, got, c.want)
		}
	}
}

func TestUptime(t *testing.T) {
	cases := []struct {
		sec  int64
		want string
	}{
		{0, "-"},
		{-5, "-"},
		{59, "0m"},
		{180, "3m"},
		{3600, "1h"},
		{5 * 3600, "5h"},
		{86400, "1d"},
		{3542400, "41d"},
	}
	for _, c := range cases {
		if got := Uptime(c.sec); got != c.want {
			t.Errorf("Uptime(%d) = %q, want %q", c.sec, got, c.want)
		}
	}
}

func TestPartition(t *testing.T) {
	policies := map[string]Policy{
		"galleta": {RebootLast: true},
	}
	normal, last := Partition([]string{"qube", "galleta", "pi4", "pi3"}, policies)
	if want := []string{"pi3", "pi4", "qube"}; !reflect.DeepEqual(normal, want) {
		t.Errorf("normal = %v, want %v", normal, want)
	}
	if want := []string{"galleta"}; !reflect.DeepEqual(last, want) {
		t.Errorf("last = %v, want %v", last, want)
	}
}

func TestChecks(t *testing.T) {
	policies := map[string]Policy{
		"qube":    {Checks: []string{"monitoring"}},
		"galleta": {Checks: []string{"galleta", "monitoring"}},
	}
	got := Checks([]string{"qube", "galleta", "pi3"}, policies)
	if want := []string{"galleta", "monitoring"}; !reflect.DeepEqual(got, want) {
		t.Errorf("Checks = %v, want %v", got, want)
	}
	if got := Checks([]string{"pi3"}, policies); got != nil {
		t.Errorf("Checks(pi3) = %v, want nil", got)
	}
}
