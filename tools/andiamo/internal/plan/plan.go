// Package plan holds the pure decision logic of andiamo: status
// classification, the reboot-necessity check, and deploy ordering.
// Nothing here performs I/O.
package plan

import (
	"sort"
	"strconv"
	"strings"
)

// Host is one entry derived from the flake's nixosConfigurations.
type Host struct {
	Name     string
	Toplevel string // expected system toplevel store path
	System   string // e.g. x86_64-linux
	Sshable  bool   // mynixcfg.ssh-server.enable
	HostName string // networking.hostName
}

// Policy is per-host deployment policy, read from each host's
// _module.args.andiamo attrset.
type Policy struct {
	Checks     []string
	RebootLast bool
}

// Links are the boot-critical symlink targets of a system toplevel.
// A change in any of them means switch-to-configuration cannot fully
// apply the new system without a reboot.
type Links struct {
	Kernel        string
	Initrd        string
	KernelModules string
	Systemd       string
}

// Complete reports whether every link was resolved.
func (l Links) Complete() bool {
	return l.Kernel != "" && l.Initrd != "" && l.KernelModules != "" && l.Systemd != ""
}

// Probe is the observed state of one host.
type Probe struct {
	Err          error
	Current      string // readlink -f /run/current-system
	Booted       string // readlink -f /run/booted-system
	Profile      string // readlink -f /nix/var/nix/profiles/system
	CurrentLinks Links
	BootedLinks  Links
	Generation   int    // from the profile symlink name; 0 = unknown
	DeployedAt   int64  // epoch mtime of the profile symlink; 0 = unknown
	NixosVersion string // /run/current-system/nixos-version
	UptimeSec    int64  // /proc/uptime; 0 = unknown
	Kernel       string // uname -r (the booted kernel)
}

type State string

const (
	InSync        State = "in-sync"
	RebootPending State = "reboot-pending"
	Staged        State = "staged-awaiting-reboot"
	OutOfDate     State = "out-of-date"
	Unreachable   State = "unreachable"
	LocalOnly     State = "local-only"
)

// NeedsReboot reports whether activating next on a machine currently
// booted with booted requires a reboot. Unresolvable links fail safe
// toward rebooting.
func NeedsReboot(next, booted Links) bool {
	if !next.Complete() || !booted.Complete() {
		return true
	}
	return next != booted
}

// Classify determines the state of a host given its expected toplevel
// and a probe. reachable is false for hosts that can neither be sshed
// to nor activated locally.
func Classify(expected string, reachable bool, p Probe) State {
	switch {
	case !reachable:
		return LocalOnly
	case p.Err != nil:
		return Unreachable
	case p.Profile != expected:
		return OutOfDate
	case p.Current != expected:
		return Staged
	case p.Booted == expected:
		return InSync
	case NeedsReboot(p.CurrentLinks, p.BootedLinks):
		return RebootPending
	default:
		return InSync
	}
}

// Partition splits host names into the normal deploy wave and the
// rebootLast wave (e.g. the router, whose reboot severs the path to
// everything behind it). Both slices are sorted for stable output.
func Partition(names []string, policies map[string]Policy) (normal, last []string) {
	for _, n := range names {
		if policies[n].RebootLast {
			last = append(last, n)
		} else {
			normal = append(normal, n)
		}
	}
	sort.Strings(normal)
	sort.Strings(last)
	return normal, last
}

// ParseGeneration extracts the generation number from a system profile
// link name like "system-143-link". Returns 0 when unparsable.
func ParseGeneration(link string) int {
	base := link
	if i := strings.LastIndexByte(base, '/'); i >= 0 {
		base = base[i+1:]
	}
	if !strings.HasPrefix(base, "system-") || !strings.HasSuffix(base, "-link") {
		return 0
	}
	n, err := strconv.Atoi(strings.TrimSuffix(strings.TrimPrefix(base, "system-"), "-link"))
	if err != nil || n < 0 {
		return 0
	}
	return n
}

// NixpkgsRev extracts the nixpkgs revision from a nixos-version string
// like "26.05.20260809.fcb8fcd" (the last dot-segment). Returns ""
// when the string doesn't look versioned.
func NixpkgsRev(version string) string {
	i := strings.LastIndexByte(version, '.')
	if i < 0 || i == len(version)-1 {
		return ""
	}
	return version[i+1:]
}

// Checks returns the deduplicated, sorted union of check gates for the
// given hosts.
func Checks(names []string, policies map[string]Policy) []string {
	seen := map[string]bool{}
	var out []string
	for _, n := range names {
		for _, c := range policies[n].Checks {
			if !seen[c] {
				seen[c] = true
				out = append(out, c)
			}
		}
	}
	sort.Strings(out)
	return out
}
