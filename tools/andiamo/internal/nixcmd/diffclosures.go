package nixcmd

import (
	"context"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// PkgDiff is one package's change between two closures — one line of
// `nix store diff-closures`. Crucially, nix prints the version-set
// DIFFERENCES, not the full sets: Removed holds the versions only the
// old closure had, Added those only the new one has. A package can
// gain a version while keeping another (glibc: ∅ → 2.42-51 on a
// system whose separately-pinned kernel tree drags in a second
// glibc), so a nil Removed does not mean the package is new to the
// closure — that is also how an "added" version can come with a
// negative SizeDelta. Both sets nil with a non-zero SizeDelta means
// the same versions with changed contents. The pseudo-version "ε" is
// nix's marker for a store path with no version in its name.
type PkgDiff struct {
	Name      string
	Removed   []string // versions only the old closure has (left of →); nil = ∅
	Added     []string // versions only the new closure has; nil = ∅
	SizeDelta int64    // bytes, over all the package's paths; 0 = not reported
}

// DiffClosures compares two store paths' closures with `nix store
// diff-closures`. Both paths must be in the local store. Identical
// closures yield an empty diff.
func DiffClosures(ctx context.Context, before, after string) ([]PkgDiff, error) {
	out, err := run(ctx, nil, "nix", "store", "diff-closures", before, after)
	if err != nil {
		return nil, err
	}
	return parseDiffClosures(out)
}

// parseDiffClosures parses diff-closures output, preserving nix's
// line order (sorted by package name). An unrecognized line is an
// error rather than a silent drop: the command is experimental, and a
// format drift should fail loudly, not thin out the diff.
func parseDiffClosures(out string) ([]PkgDiff, error) {
	var diffs []PkgDiff
	for _, line := range strings.Split(out, "\n") {
		line = strings.TrimSpace(ansiRE.ReplaceAllString(line, ""))
		if line == "" {
			continue
		}
		d, err := parseDiffLine(line)
		if err != nil {
			return nil, err
		}
		diffs = append(diffs, d)
	}
	return diffs, nil
}

// parseDiffLine parses one line. The observed grammar (each side of
// the arrow is a version-set difference, see PkgDiff):
//
//	name: 1.2 → 1.3                      version change, no size delta
//	name: 1.2 → 1.3, +1.2 MiB            with size delta
//	name: ∅ → 1.3, -4.0 KiB              version gained (delta can be negative)
//	name: 1.2 → ∅, -6.5 MiB              version dropped
//	name: 1.2, 1.2-fhs → 1.3, 1.3-fhs    several versions per side
//	name: ε → ∅                          version-less store path dropped
//	name: +120.2 KiB                     same versions, contents changed
//
// When nix colors the output the sign of a positive delta is carried
// by the color alone (no "+"), so the sign is optional. A size always
// contains a space and a unit; versions never contain spaces — that
// distinguishes a trailing size from a last version.
func parseDiffLine(line string) (PkgDiff, error) {
	name, rest, ok := strings.Cut(line, ": ")
	if !ok || name == "" || rest == "" {
		return PkgDiff{}, fmt.Errorf("diff-closures: unrecognized line %q", line)
	}
	d := PkgDiff{Name: name}
	before, after, hasArrow := strings.Cut(rest, " → ")
	if !hasArrow {
		// The whole rest must be a size delta.
		n, ok := parseSizeDelta(rest)
		if !ok {
			return PkgDiff{}, fmt.Errorf("diff-closures: unrecognized line %q", line)
		}
		d.SizeDelta = n
		return d, nil
	}
	if i := strings.LastIndex(after, ", "); i >= 0 {
		if n, ok := parseSizeDelta(after[i+2:]); ok {
			d.SizeDelta = n
			after = after[:i]
		}
	}
	d.Removed = versionSet(before)
	d.Added = versionSet(after)
	return d, nil
}

// versionSet splits a comma-separated version list; ∅ means absent.
func versionSet(s string) []string {
	if s == "∅" {
		return nil
	}
	return strings.Split(s, ", ")
}

var sizeDeltaRE = regexp.MustCompile(`^([+-]?[0-9]+(?:\.[0-9]+)?) (B|KiB|MiB|GiB|TiB)$`)

var sizeUnits = map[string]float64{
	"B": 1, "KiB": 1 << 10, "MiB": 1 << 20, "GiB": 1 << 30, "TiB": 1 << 40,
}

// parseSizeDelta converts "±N.N KiB" to bytes.
func parseSizeDelta(s string) (int64, bool) {
	m := sizeDeltaRE.FindStringSubmatch(s)
	if m == nil {
		return 0, false
	}
	v, err := strconv.ParseFloat(m[1], 64)
	if err != nil {
		return 0, false
	}
	return int64(v * sizeUnits[m[2]]), true
}
