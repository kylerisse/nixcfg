package nixcmd

import "testing"

func TestLineWriter(t *testing.T) {
	var seen []string
	w := &LineWriter{Fn: func(s string) { seen = append(seen, s) }}
	// Lines arrive split across writes; the last one has no newline.
	_, _ = w.Write([]byte("evaluating file 'a.nix'\nwarn"))
	_, _ = w.Write([]byte("ing: dirty\nevaluating file 'b.nix'\nerror: boom"))
	if len(seen) != 3 || seen[1] != "warning: dirty" || seen[2] != "evaluating file 'b.nix'" {
		t.Fatalf("before flush: %q", seen)
	}
	w.Flush()
	w.Flush() // idempotent
	want := []string{"evaluating file 'a.nix'", "warning: dirty", "evaluating file 'b.nix'", "error: boom"}
	if len(seen) != len(want) {
		t.Fatalf("seen = %q, want %q", seen, want)
	}
	for i := range want {
		if seen[i] != want[i] {
			t.Errorf("seen[%d] = %q, want %q", i, seen[i], want[i])
		}
	}
}
