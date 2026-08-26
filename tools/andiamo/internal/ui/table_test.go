package ui

import "testing"

func TestWidth(t *testing.T) {
	cases := []struct {
		in   string
		want int
	}{
		{"", 0},
		{"abc", 3},
		{"✓", 1},
		{"6.18.46 → 7.2", 13},
		{"\x1b[32min sync\x1b[0m", 7},
		{"\x1b[1m\x1b[33m↻\x1b[0m", 1},
	}
	for _, c := range cases {
		if got := Width(c.in); got != c.want {
			t.Errorf("Width(%q) = %d, want %d", c.in, got, c.want)
		}
	}
}

func TestTable(t *testing.T) {
	rows := [][]string{
		{"", "HOST", "STATE", "REV", ""},
		{"✓", "gibson", "\x1b[32min sync\x1b[0m", "a61d215", ""},
		{"↻", "pi4", "out of date", "30f1e1c → a61d215", "reboot-last wave"},
		{"~", "pi3", "unreachable", "-", "ssh: connect timeout"},
	}
	want := "" +
		"   HOST    STATE        REV\n" +
		"✓  gibson  \x1b[32min sync\x1b[0m      a61d215\n" +
		"↻  pi4     out of date  30f1e1c → a61d215  reboot-last wave\n" +
		"~  pi3     unreachable  -                  ssh: connect timeout\n"
	if got := Table(rows); got != want {
		t.Errorf("Table mismatch\n got: %q\nwant: %q", got, want)
	}
}

func TestTableRaggedRows(t *testing.T) {
	// Short rows are padded with empty cells; a single column has no
	// trailing padding at all.
	got := Table([][]string{{"a", "b"}, {"longer"}})
	if want := "a       b\nlonger\n"; got != want {
		t.Errorf("Table = %q, want %q", got, want)
	}
	if got := Table(nil); got != "" {
		t.Errorf("Table(nil) = %q, want empty", got)
	}
}
