package remote

import (
	"strings"
	"testing"
)

// canned is what probeScript prints on a healthy host, in order.
var canned = []string{
	"/nix/store/new-nixos-system-qube",
	"/nix/store/old-nixos-system-qube",
	"/nix/store/new-nixos-system-qube",
	"/nix/store/new-linux",
	"/nix/store/new-initrd",
	"/nix/store/new-mods",
	"/nix/store/new-systemd",
	"/nix/store/old-linux",
	"/nix/store/old-initrd",
	"/nix/store/old-mods",
	"/nix/store/old-systemd",
	"system-64-link",
	"1787700000",
	"26.05.20260825.f4f6986",
	"3542400",
	"6.18.46",
}

func TestParseProbe(t *testing.T) {
	p := parseProbe(strings.Join(canned, "\n"))
	if p.Err != nil {
		t.Fatalf("unexpected error: %v", p.Err)
	}
	if p.Current != canned[0] || p.Booted != canned[1] || p.Profile != canned[2] {
		t.Errorf("system links = %q %q %q", p.Current, p.Booted, p.Profile)
	}
	if p.CurrentLinks.Kernel != "/nix/store/new-linux" || p.BootedLinks.Systemd != "/nix/store/old-systemd" {
		t.Errorf("boot-critical links mis-mapped: %+v %+v", p.CurrentLinks, p.BootedLinks)
	}
	if p.Generation != 64 {
		t.Errorf("Generation = %d, want 64", p.Generation)
	}
	if p.DeployedAt != 1787700000 {
		t.Errorf("DeployedAt = %d", p.DeployedAt)
	}
	if p.NixosVersion != "26.05.20260825.f4f6986" {
		t.Errorf("NixosVersion = %q", p.NixosVersion)
	}
	if p.UptimeSec != 3542400 {
		t.Errorf("UptimeSec = %d", p.UptimeSec)
	}
	if p.Kernel != "6.18.46" {
		t.Errorf("Kernel = %q", p.Kernel)
	}
}

func TestParseProbeMissing(t *testing.T) {
	lines := append([]string{}, canned...)
	lines[1] = "MISSING"  // no /run/booted-system
	lines[12] = "0"       // stat failed
	lines[14] = "0"       // no /proc/uptime
	lines[15] = "MISSING" // uname failed
	p := parseProbe(strings.Join(lines, "\n"))
	if p.Err != nil {
		t.Fatalf("unexpected error: %v", p.Err)
	}
	if p.Booted != "" || p.DeployedAt != 0 || p.UptimeSec != 0 || p.Kernel != "" {
		t.Errorf("missing values not zeroed: %+v", p)
	}
}

func TestParseProbeLineCount(t *testing.T) {
	p := parseProbe(strings.Join(canned[:len(canned)-1], "\n"))
	if p.Err == nil {
		t.Error("short output must be an error, not a misaligned probe")
	}
	if p.Err != nil && !strings.Contains(p.Err.Error(), "want 16") {
		t.Errorf("error should name the expected count: %v", p.Err)
	}
}
