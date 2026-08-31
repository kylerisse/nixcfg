package confdiff

import (
	"context"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
)

// hash32 is a valid 32-character nix base-32 hash (the alphabet
// itself, which is exactly 32 characters).
const hash32 = "0123456789abcdfghijklmnpqrsvwxyz"
const hash32b = "zyxwvsrqpnmlkjihgfdcba9876543210"

func TestNormalize(t *testing.T) {
	in := "wrap /nix/store/" + hash32 + "-pkg-1.0/bin/x and /nix/store/" + hash32b + "-other"
	want := "wrap /nix/store/…-pkg-1.0/bin/x and /nix/store/…-other"
	if got := string(Normalize([]byte(in))); got != want {
		t.Errorf("Normalize = %q, want %q", got, want)
	}
	// Wrong length or invalid chars (e is not in the alphabet): untouched.
	for _, s := range []string{
		"/nix/store/short-pkg",
		"/nix/store/e123456789abcdfghijklmnpqrsvwxy-pkg",
	} {
		if got := string(Normalize([]byte(s))); got != s {
			t.Errorf("Normalize(%q) = %q, want unchanged", s, got)
		}
	}
}

// writeFile creates path (and parents) with content.
func writeFile(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func TestEtc(t *testing.T) {
	dir := t.TempDir()
	oldTop, newTop := filepath.Join(dir, "old"), filepath.Join(dir, "new")

	// Same content behind different store hashes: must be omitted.
	writeFile(t, filepath.Join(oldTop, "etc/hash-only.conf"), "exec /nix/store/"+hash32+"-tool/bin/t\n")
	writeFile(t, filepath.Join(newTop, "etc/hash-only.conf"), "exec /nix/store/"+hash32b+"-tool/bin/t\n")
	// Real content change.
	writeFile(t, filepath.Join(oldTop, "etc/app.conf"), "port = 80\n")
	writeFile(t, filepath.Join(newTop, "etc/app.conf"), "port = 443\n")
	// Added and removed files.
	writeFile(t, filepath.Join(newTop, "etc/new.conf"), "hello\n")
	writeFile(t, filepath.Join(oldTop, "etc/gone.conf"), "bye\n")
	// Dangling symlink retargeted.
	if err := os.Symlink("/proc/self/mounts", filepath.Join(oldTop, "etc/mtab")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("/proc/mounts", filepath.Join(newTop, "etc/mtab")); err != nil {
		t.Fatal(err)
	}

	changes, err := Etc(context.Background(), oldTop, newTop)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	got := map[string]Kind{}
	for _, c := range changes {
		got[c.Path] = c.Kind
	}
	want := map[string]Kind{
		"etc/app.conf":  Changed,
		"etc/new.conf":  Added,
		"etc/gone.conf": Removed,
		"etc/mtab":      Changed,
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("changes = %v, want %v", got, want)
	}
	for _, c := range changes {
		if c.Path != "etc/app.conf" {
			continue
		}
		body := strings.Join(c.Diff, "\n")
		if !strings.Contains(body, "-port = 80") || !strings.Contains(body, "+port = 443") {
			t.Errorf("app.conf diff missing content:\n%s", body)
		}
	}
}

func TestCommands(t *testing.T) {
	dir := t.TempDir()
	oldTop, newTop := filepath.Join(dir, "old"), filepath.Join(dir, "new")
	writeFile(t, filepath.Join(oldTop, "sw/bin/ag"), "")
	writeFile(t, filepath.Join(oldTop, "sw/bin/ls"), "")
	writeFile(t, filepath.Join(newTop, "sw/bin/rg"), "")
	writeFile(t, filepath.Join(newTop, "sw/bin/ls"), "")
	added, removed, err := Commands(oldTop, newTop)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if !reflect.DeepEqual(added, []string{"rg"}) || !reflect.DeepEqual(removed, []string{"ag"}) {
		t.Errorf("added %v removed %v, want [rg] [ag]", added, removed)
	}
}

func TestEtcIdentical(t *testing.T) {
	dir := t.TempDir()
	oldTop, newTop := filepath.Join(dir, "old"), filepath.Join(dir, "new")
	writeFile(t, filepath.Join(oldTop, "etc/same.conf"), "x\n")
	writeFile(t, filepath.Join(newTop, "etc/same.conf"), "x\n")
	changes, err := Etc(context.Background(), oldTop, newTop)
	if err != nil || changes != nil {
		t.Errorf("identical trees: changes %v, err %v", changes, err)
	}
}

func TestEtcFollowsChangedReferences(t *testing.T) {
	dir := t.TempDir()
	store := filepath.Join(dir, "store")
	orig := storeRoot
	storeRoot = store
	defer func() { storeRoot = orig }()

	// A two-level pointer chain, like unit → named.conf → zone file:
	// the zone content changes, everything above only retargets.
	zoneOld, zoneNew := hash32+"-zone.example", hash32b+"-zone.example"
	writeFile(t, filepath.Join(store, zoneOld), "a IN A 192.168.73.2\n")
	writeFile(t, filepath.Join(store, zoneNew), "a IN A 192.168.73.2\nb IN CNAME a\n")
	confOld, confNew := hash32+"-app.conf", hash32b+"-app.conf"
	writeFile(t, filepath.Join(store, confOld), "zone \"/nix/store/"+zoneOld+"\";\n")
	writeFile(t, filepath.Join(store, confNew), "zone \"/nix/store/"+zoneNew+"\";\n")

	oldTop, newTop := filepath.Join(dir, "old"), filepath.Join(dir, "new")
	writeFile(t, filepath.Join(oldTop, "etc/unit.service"), "ExecStart=daemon -c /nix/store/"+confOld+"\n")
	writeFile(t, filepath.Join(newTop, "etc/unit.service"), "ExecStart=daemon -c /nix/store/"+confNew+"\n")
	// A second referrer of the same pair must not duplicate the report.
	writeFile(t, filepath.Join(oldTop, "etc/pre-start"), "check /nix/store/"+confOld+"\n")
	writeFile(t, filepath.Join(newTop, "etc/pre-start"), "check /nix/store/"+confNew+"\n")

	changes, err := Etc(context.Background(), oldTop, newTop)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(changes) != 1 {
		t.Fatalf("changes = %+v, want exactly the chased zone change", changes)
	}
	c := changes[0]
	if c.Path != "etc/pre-start → app.conf → zone.example" || c.Kind != Changed {
		t.Errorf("change = %+v", c)
	}
	if body := strings.Join(c.Diff, "\n"); !strings.Contains(body, "+b IN CNAME a") {
		t.Errorf("diff missing zone record:\n%s", body)
	}
}

func TestEtcIgnoresNonFileReferences(t *testing.T) {
	dir := t.TempDir()
	store := filepath.Join(dir, "store")
	orig := storeRoot
	storeRoot = store
	defer func() { storeRoot = orig }()
	// Retargeted references to directories are not chased.
	if err := os.MkdirAll(filepath.Join(store, hash32+"-pkg"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(store, hash32b+"-pkg"), 0o755); err != nil {
		t.Fatal(err)
	}
	oldTop, newTop := filepath.Join(dir, "old"), filepath.Join(dir, "new")
	writeFile(t, filepath.Join(oldTop, "etc/wrapper"), "exec /nix/store/"+hash32+"-pkg/bin/x\n")
	writeFile(t, filepath.Join(newTop, "etc/wrapper"), "exec /nix/store/"+hash32b+"-pkg/bin/x\n")
	changes, err := Etc(context.Background(), oldTop, newTop)
	if err != nil || changes != nil {
		t.Errorf("directory refs: changes %v, err %v, want none", changes, err)
	}
}

func TestEtcDescendsDirSymlinks(t *testing.T) {
	dir := t.TempDir()
	oldTop, newTop := filepath.Join(dir, "old"), filepath.Join(dir, "new")
	// A whole subtree behind one directory symlink, like
	// etc/systemd/system on NixOS (relative target, same semantics).
	writeFile(t, filepath.Join(oldTop, "units-real/foo.conf"), "mode = a\n")
	writeFile(t, filepath.Join(newTop, "units-real/foo.conf"), "mode = b\n")
	if err := os.MkdirAll(filepath.Join(oldTop, "etc"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.MkdirAll(filepath.Join(newTop, "etc"), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("../units-real", filepath.Join(oldTop, "etc/units")); err != nil {
		t.Fatal(err)
	}
	if err := os.Symlink("../units-real", filepath.Join(newTop, "etc/units")); err != nil {
		t.Fatal(err)
	}
	changes, err := Etc(context.Background(), oldTop, newTop)
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if len(changes) != 1 || changes[0].Path != "etc/units/foo.conf" || changes[0].Kind != Changed {
		t.Fatalf("changes = %+v, want changed etc/units/foo.conf", changes)
	}
}
