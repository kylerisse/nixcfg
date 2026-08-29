package ui

import "testing"

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
