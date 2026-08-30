package ui

import (
	"os"
	"testing"
)

func TestTruncate(t *testing.T) {
	cases := []struct {
		name string
		in   string
		max  int
		want string
	}{
		{"fits", "abc", 5, "abc"},
		{"exact", "abcde", 5, "abcde"},
		{"plain cut", "abcdefgh", 3, "abc"},
		{"zero", "abc", 0, ""},
		{"multibyte", "✓ pi3  evaluating  3s", 5, "✓ pi3"},
		{"cut inside colour", "\x1b[32mabcdef\x1b[0m", 3, "\x1b[32mabc\x1b[0m"},
		{"cut after reset", "\x1b[32mab\x1b[0mcdef", 3, "\x1b[32mab\x1b[0mc"},
		{"cut before colour starts", "abc\x1b[2mdef\x1b[0m", 2, "ab"},
		{"colour only counted as zero", "\x1b[1m\x1b[33m↻\x1b[0m", 1, "\x1b[1m\x1b[33m↻\x1b[0m"},
	}
	for _, c := range cases {
		if got := Truncate(c.in, c.max); got != c.want {
			t.Errorf("%s: Truncate(%q, %d) = %q, want %q", c.name, c.in, c.max, got, c.want)
		}
	}
}

func TestProgressDetail(t *testing.T) {
	liveEnabled = false
	p := NewProgress([]string{"pi3"})
	p.Detail("pi3", "nixpkgs/nixos/modules/config/console.nix")
	if p.rows["pi3"].detail == "" {
		t.Fatal("Detail before Set was dropped")
	}
	p.Set("pi3", "evaluating")
	p.Detail("pi3", "modules/nix-common/default.nix")
	if got := p.rows["pi3"].detail; got != "modules/nix-common/default.nix" {
		t.Errorf("detail = %q", got)
	}
	p.Done("pi3", true, "evaluated")
	if p.rows["pi3"].detail != "" {
		t.Error("Done did not clear detail")
	}
	p.Detail("pi3", "late")
	if p.rows["pi3"].detail != "" {
		t.Error("Detail after Done was accepted")
	}
	p.Close()
}

func TestIsTTY(t *testing.T) {
	null, err := os.Open(os.DevNull)
	if err != nil {
		t.Fatal(err)
	}
	defer null.Close()
	if IsTTY(null) {
		t.Error("IsTTY(/dev/null) = true; a character device is not a terminal")
	}
	r, w, err := os.Pipe()
	if err != nil {
		t.Fatal(err)
	}
	defer r.Close()
	defer w.Close()
	if IsTTY(w) {
		t.Error("IsTTY(pipe) = true")
	}
}

func TestScrub(t *testing.T) {
	const in = "\x1b[2mserver # \x1b[0mok\tdone\x1b[K\x1b[1;32m✓\x1b[m\x1b]0;title\x07\x1b"
	colorEnabled = false
	if got, want := Scrub(in), "server # ok done✓"; got != want {
		t.Errorf("colour off: %q, want %q", got, want)
	}
	colorEnabled = true
	defer func() { colorEnabled = false }()
	want := "\x1b[2mserver # \x1b[0m\x1b[2mok done\x1b[1;32m✓\x1b[0m\x1b[2m"
	if got := Scrub(in); got != want {
		t.Errorf("colour on: %q, want %q", got, want)
	}
	// What the row renders: a dim detail whose inner reset no longer
	// un-dims the tail, and whose width is still counted right.
	if w := Width(Dim(Scrub(in))); w != 17 {
		t.Errorf("visible width = %d, want 17", w)
	}
}
