package flake

import "testing"

func TestHashKey(t *testing.T) {
	a := hashKey("head", "diff", "nix 2.30", "expr")
	if b := hashKey("head", "diff", "nix 2.30", "expr"); b != a {
		t.Errorf("hashKey not stable: %q vs %q", a, b)
	}
	// Every component must influence the key.
	variants := [][]string{
		{"HEAD", "diff", "nix 2.30", "expr"},
		{"head", "DIFF", "nix 2.30", "expr"},
		{"head", "diff", "nix 2.31", "expr"},
		{"head", "diff", "nix 2.30", "expr2"},
	}
	for _, v := range variants {
		if hashKey(v...) == a {
			t.Errorf("hashKey ignored a component change: %v", v)
		}
	}
	// Concatenation ambiguity must not collide.
	if hashKey("ab", "c") == hashKey("a", "bc") {
		t.Error("hashKey collides across part boundaries")
	}
	if len(a) != 32 {
		t.Errorf("hashKey length = %d, want 32", len(a))
	}
}

func TestCacheRoundTrip(t *testing.T) {
	dir := t.TempDir()
	f := facts{
		Toplevel:     "/nix/store/abc-nixos-system-qube",
		System:       "x86_64-linux",
		Sshable:      true,
		HostName:     "qube",
		NixosVersion: "26.05.20260825.f4f6986",
		Kernel:       "7.2.0",
		Checks:       []string{"monitoring"},
		RebootLast:   false,
	}
	if _, ok := loadCached(dir, "key1", "qube"); ok {
		t.Fatal("unexpected cache hit in empty dir")
	}
	storeCached(dir, "key1", "qube", f)
	got, ok := loadCached(dir, "key1", "qube")
	if !ok {
		t.Fatal("expected cache hit after store")
	}
	if got.Toplevel != f.Toplevel || got.HostName != f.HostName ||
		got.NixosVersion != f.NixosVersion || got.Kernel != f.Kernel ||
		len(got.Checks) != 1 || got.Checks[0] != "monitoring" || !got.Sshable {
		t.Errorf("round trip mismatch: %+v", got)
	}
	// A different tree key must miss.
	if _, ok := loadCached(dir, "key2", "qube"); ok {
		t.Error("cache hit across different tree keys")
	}
	// A record without a toplevel is treated as corrupt.
	storeCached(dir, "key3", "qube", facts{HostName: "qube"})
	if _, ok := loadCached(dir, "key3", "qube"); ok {
		t.Error("cache hit on record with empty toplevel")
	}
}

func TestCheckCacheRoundTrip(t *testing.T) {
	dir := t.TempDir()
	f := checkFacts{Drv: "/nix/store/abc-vm-test-run-galleta.drv", Out: "/nix/store/def-vm-test-run-galleta"}
	if _, ok := loadCachedCheck(dir, "key1", "galleta"); ok {
		t.Fatal("unexpected cache hit in empty dir")
	}
	storeCachedCheck(dir, "key1", "galleta", f)
	if got, ok := loadCachedCheck(dir, "key1", "galleta"); !ok || got != f {
		t.Errorf("round trip: ok=%v got=%+v", ok, got)
	}
	// Host and check records never collide, even on the same name.
	if _, ok := loadCached(dir, "key1", "galleta"); ok {
		t.Error("check record served as a host record")
	}
	storeCachedCheck(dir, "key2", "galleta", checkFacts{Drv: "/nix/store/x.drv"})
	if _, ok := loadCachedCheck(dir, "key2", "galleta"); ok {
		t.Error("cache hit on record with empty out")
	}
}
