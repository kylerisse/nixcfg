// Package confdiff renders the config-level difference between two
// system toplevels: their rendered /etc trees and the commands their
// system path exposes. Store hashes are normalised away first, so a
// file that merely re-references rebuilt store paths compares equal
// and only real content changes surface. When a reference was
// retargeted, though, the referenced store file's own content is
// compared — recursively — so a config that lives behind a pointer
// chain (a systemd unit naming named.conf naming a zone file) still
// shows its real change. This complements the closure diff, which can
// see neither re-wired store paths nor content changes hiding behind
// same-name, version-less store paths.
package confdiff

import (
	"bytes"
	"context"
	"fmt"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
)

// storeHashRE matches the hash component of a store path. Nix's
// base-32 alphabet excludes e, o, t, and u.
var storeHashRE = regexp.MustCompile(`/nix/store/[0-9abcdfghijklmnpqrsvwxyz]{32}-`)

// Normalize replaces every store path hash with … so two files that
// differ only in the hashes of the paths they reference compare
// equal.
func Normalize(b []byte) []byte {
	return storeHashRE.ReplaceAll(b, []byte("/nix/store/…-"))
}

// storeRefRE captures a full store path reference (hash-name).
var storeRefRE = regexp.MustCompile(`/nix/store/([0-9abcdfghijklmnpqrsvwxyz]{32}-[0-9a-zA-Z+._?=-]+)`)

// storeRoot is where referenced store paths are read from. A var so
// tests can point it at a fake store.
var storeRoot = "/nix/store"

type Kind byte

const (
	Added Kind = iota
	Removed
	Changed
)

// Change is one file's difference between two etc trees. Path is the
// file's path relative to the toplevel, or a reference chain like
// "etc/systemd/system/bind.service → named.conf → named.example.com"
// when the change hides behind retargeted store references.
type Change struct {
	Path string
	Kind Kind
	Diff []string // unified diff hunks for Changed (headers stripped); nil otherwise
}

// content is one etc file's raw and normalised bytes. The raw form
// keeps the store hashes, which is what reference-following needs.
type content struct {
	raw, norm []byte
}

// Etc compares the rendered etc trees of two toplevels, both present
// in the local store. Files whose normalised contents match are
// omitted — including every file that changed only because store
// paths it references were rebuilt — but references that changed
// target are followed and their contents compared (see Change).
func Etc(ctx context.Context, oldTop, newTop string) ([]Change, error) {
	oldFiles, err := readTree(filepath.Join(oldTop, "etc"))
	if err != nil {
		return nil, err
	}
	newFiles, err := readTree(filepath.Join(newTop, "etc"))
	if err != nil {
		return nil, err
	}
	paths := make([]string, 0, len(oldFiles)+len(newFiles))
	for p := range oldFiles {
		paths = append(paths, p)
	}
	for p := range newFiles {
		if _, ok := oldFiles[p]; !ok {
			paths = append(paths, p)
		}
	}
	sort.Strings(paths)
	chaser := &refChaser{ctx: ctx, visited: map[string]bool{}}
	var changes []Change
	for _, p := range paths {
		o, hasO := oldFiles[p]
		n, hasN := newFiles[p]
		rel := filepath.Join("etc", p)
		switch {
		case !hasO:
			changes = append(changes, Change{Path: rel, Kind: Added})
		case !hasN:
			changes = append(changes, Change{Path: rel, Kind: Removed})
		case !bytes.Equal(o.norm, n.norm):
			d, err := unified(ctx, o.norm, n.norm)
			if err != nil {
				return nil, fmt.Errorf("%s: %w", rel, err)
			}
			changes = append(changes, Change{Path: rel, Kind: Changed, Diff: d})
		}
		if hasO && hasN && !bytes.Equal(o.raw, n.raw) {
			chaser.follow(o.raw, n.raw, rel, 3, &changes)
		}
	}
	return changes, nil
}

// refChaser follows store references that changed target, comparing
// the referenced files' contents. visited dedupes pairs fleet-wide
// within one Etc call (many units reference the same binaries) and
// bounds the walk.
type refChaser struct {
	ctx     context.Context
	visited map[string]bool
}

// maxVisited bounds the total pairs examined per Etc call; a nixpkgs
// bump retargets thousands of references, almost all of them to
// binaries and directories the size/type filters reject cheaply.
const maxVisited = 400

// follow pairs up old and new references by their hash-less name and
// position, and for each retargeted pair diffs the referenced files'
// normalised contents — emitting a Change on a real difference — then
// recurses to chase pointer chains.
func (c *refChaser) follow(oldRaw, newRaw []byte, via string, depth int, out *[]Change) {
	if depth == 0 || len(c.visited) > maxVisited {
		return
	}
	oldRefs := refsByName(oldRaw)
	newRefs := refsByName(newRaw)
	names := make([]string, 0, len(oldRefs))
	for name := range oldRefs {
		if _, ok := newRefs[name]; ok {
			names = append(names, name)
		}
	}
	sort.Strings(names)
	for _, name := range names {
		olds, news := oldRefs[name], newRefs[name]
		for i := 0; i < len(olds) && i < len(news); i++ {
			a, b := olds[i], news[i]
			if a == b || c.visited[a+"→"+b] {
				continue
			}
			c.visited[a+"→"+b] = true
			ca, ok := readSmallText(filepath.Join(storeRoot, a))
			if !ok {
				continue
			}
			cb, ok := readSmallText(filepath.Join(storeRoot, b))
			if !ok {
				continue
			}
			label := via + " → " + name
			na, nb := Normalize(ca), Normalize(cb)
			if !bytes.Equal(na, nb) {
				if d, err := unified(c.ctx, na, nb); err == nil {
					*out = append(*out, Change{Path: label, Kind: Changed, Diff: d})
				}
			}
			c.follow(ca, cb, label, depth-1, out)
		}
	}
}

// refsByName groups a file's store references by their hash-less
// name, in order of appearance, so retargeted references pair up by
// name and position.
func refsByName(raw []byte) map[string][]string {
	refs := map[string][]string{}
	for _, m := range storeRefRE.FindAllSubmatch(raw, -1) {
		full := string(m[1]) // hash-name
		name := full[33:]    // skip hash and dash
		refs[name] = append(refs[name], full)
	}
	return refs
}

// readSmallText reads a store path when it is a regular text file of
// reasonable size; anything else (directory, binary, huge) is not a
// config file worth chasing.
func readSmallText(path string) ([]byte, bool) {
	info, err := os.Stat(path)
	if err != nil || !info.Mode().IsRegular() || info.Size() > 512*1024 {
		return nil, false
	}
	data, err := os.ReadFile(path)
	if err != nil || bytes.IndexByte(data, 0) >= 0 {
		return nil, false
	}
	return data, true
}

// readTree loads every file under the toplevel's etc directory keyed
// by relative path. Directory symlinks are descended — NixOS mounts
// whole subtrees like etc/systemd/system through a single link into
// the store. File symlinks into the store or within the tree are read
// through: their content is the declared config. One that points
// elsewhere (/proc/mounts, /var/…) is recorded as its target instead:
// that's live system state, not configuration, and reading it would
// diff the weather.
func readTree(root string) (map[string]content, error) {
	root, err := filepath.EvalSymlinks(root)
	if err != nil {
		return nil, err
	}
	files := map[string]content{}
	record := func(rel string, raw []byte) {
		files[rel] = content{raw: raw, norm: Normalize(raw)}
	}
	var walk func(dir, rel string, depth int) error
	walk = func(dir, rel string, depth int) error {
		if depth > 40 { // symlink cycle guard
			return nil
		}
		entries, err := os.ReadDir(dir)
		if err != nil {
			return err
		}
		for _, e := range entries {
			full := filepath.Join(dir, e.Name())
			r := e.Name()
			if rel != "" {
				r = rel + "/" + e.Name()
			}
			switch {
			case e.IsDir():
				if err := walk(full, r, depth+1); err != nil {
					return err
				}
			case e.Type()&fs.ModeSymlink != 0:
				target, err := os.Readlink(full)
				if err != nil {
					continue
				}
				if strings.HasPrefix(target, "/") && !strings.HasPrefix(target, "/nix/store/") {
					record(r, []byte("symlink → "+target))
					continue
				}
				if info, err := os.Stat(full); err == nil && info.IsDir() {
					if err := walk(full, r, depth+1); err != nil {
						return err
					}
					continue
				}
				if data, err := os.ReadFile(full); err == nil {
					record(r, data)
				} else { // dangling: keep the declared target
					record(r, []byte("symlink → "+target))
				}
			default:
				if data, err := os.ReadFile(full); err == nil {
					record(r, data)
				}
			}
		}
		return nil
	}
	if err := walk(root, "", 0); err != nil {
		return nil, err
	}
	return files, nil
}

// Commands reports the command names the system path (sw/bin) gains
// and loses, sorted.
func Commands(oldTop, newTop string) (added, removed []string, err error) {
	list := func(top string) (map[string]bool, error) {
		entries, err := os.ReadDir(filepath.Join(top, "sw", "bin"))
		if err != nil {
			return nil, err
		}
		names := make(map[string]bool, len(entries))
		for _, e := range entries {
			names[e.Name()] = true
		}
		return names, nil
	}
	o, err := list(oldTop)
	if err != nil {
		return nil, nil, err
	}
	n, err := list(newTop)
	if err != nil {
		return nil, nil, err
	}
	for name := range n {
		if !o[name] {
			added = append(added, name)
		}
	}
	for name := range o {
		if !n[name] {
			removed = append(removed, name)
		}
	}
	sort.Strings(added)
	sort.Strings(removed)
	return added, removed, nil
}

// unified renders a unified diff of two normalised contents by
// driving the system diff. Binary contents get a one-line marker.
func unified(ctx context.Context, old, new []byte) ([]string, error) {
	if bytes.IndexByte(old, 0) >= 0 || bytes.IndexByte(new, 0) >= 0 {
		return []string{"binary contents differ"}, nil
	}
	dir, err := os.MkdirTemp("", "andiamo-confdiff")
	if err != nil {
		return nil, err
	}
	defer os.RemoveAll(dir)
	a, b := filepath.Join(dir, "old"), filepath.Join(dir, "new")
	if err := os.WriteFile(a, old, 0o600); err != nil {
		return nil, err
	}
	if err := os.WriteFile(b, new, 0o600); err != nil {
		return nil, err
	}
	out, err := exec.CommandContext(ctx, "diff", "-u", a, b).Output()
	if err != nil {
		// Exit 1 just means the files differ.
		if ee, ok := err.(*exec.ExitError); !ok || ee.ExitCode() != 1 {
			return nil, fmt.Errorf("diff: %w", err)
		}
	}
	var lines []string
	for _, l := range strings.Split(strings.TrimRight(string(out), "\n"), "\n") {
		if strings.HasPrefix(l, "--- ") || strings.HasPrefix(l, "+++ ") || l == "" {
			continue
		}
		lines = append(lines, l)
	}
	return lines, nil
}
