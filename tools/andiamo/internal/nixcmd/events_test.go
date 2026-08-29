package nixcmd

import (
	"encoding/json"
	"strings"
	"testing"
)

// A condensed real stream: a substitute (narinfo query, copy-path,
// download with byte progress) and a build with log lines, under
// the root builds/copy-paths counters.
const canned = `
{"action":"start","id":102,"level":0,"parent":0,"text":"","type":102}
{"action":"start","id":104,"level":0,"parent":0,"text":"","type":104}
{"action":"start","id":103,"level":0,"parent":0,"text":"","type":103}
{"action":"start","fields":["/nix/store/wl6xbyf0k5b14izm59rfh9rvdyjh4n68-nyancat-1.5.2","https://cache.nixos.org"],"id":967,"level":4,"parent":0,"text":"fetching","type":108}
{"action":"start","fields":["/nix/store/wl6xbyf0k5b14izm59rfh9rvdyjh4n68-nyancat-1.5.2","https://cache.nixos.org","local"],"id":968,"level":4,"parent":967,"text":"copying","type":100}
{"action":"start","fields":["https://cache.nixos.org/nar/x.nar.zst"],"id":969,"level":4,"parent":968,"text":"downloading","type":101}
{"action":"result","fields":[0,1,0,0],"id":103,"type":105}
{"action":"result","fields":[4125,15909,0,0],"id":969,"type":105}
{"action":"start","fields":["/nix/store/150zykpi9v1hhm87yf1y1b3ail40s36w-andiamo-probe.drv","",1,1],"id":135,"level":3,"parent":0,"text":"building","type":105}
{"action":"result","fields":[0,2,1,0],"id":104,"type":105}
{"action":"result","fields":["buildPhase"],"id":135,"type":104}
{"action":"result","fields":["hello"],"id":135,"type":101}
{"action":"result","fields":["world"],"id":135,"type":101}
{"action":"result","fields":[14863,15909,0,0],"id":969,"type":105}
{"action":"msg","level":3,"msg":"this path will be fetched"}
`

func feed(t *testing.T, tr *Tracker, upTo int) {
	t.Helper()
	n := 0
	for _, l := range strings.Split(strings.TrimSpace(canned), "\n") {
		if n == upTo {
			return
		}
		var e Event
		if err := json.Unmarshal([]byte(l), &e); err != nil {
			t.Fatalf("bad canned line %q: %v", l, err)
		}
		tr.Apply(e)
		n++
	}
}

func find(acts []Activity, id uint64) *Activity {
	for i := range acts {
		if acts[i].ID == id {
			return &acts[i]
		}
	}
	return nil
}

func TestTracker(t *testing.T) {
	var tr Tracker
	feed(t, &tr, -1)
	acts := tr.Snapshot()
	if len(acts) != 7 {
		t.Fatalf("live activities = %d, want 7", len(acts))
	}
	if acts[0].ID != 135 || acts[0].Type != ActBuild {
		t.Errorf("newest = %+v, want the build", acts[0])
	}
	b := find(acts, 135)
	if b.Path != "/nix/store/150zykpi9v1hhm87yf1y1b3ail40s36w-andiamo-probe.drv" || b.Phase != "buildPhase" || b.LastLine != "world" {
		t.Errorf("build activity = %+v", *b)
	}
	// Download bytes roll up to the copy-path and the substitute.
	for _, id := range []uint64{967, 968} {
		a := find(acts, id)
		if a.Path != "/nix/store/wl6xbyf0k5b14izm59rfh9rvdyjh4n68-nyancat-1.5.2" || a.Bytes != 14863 || a.BytesTotal != 15909 {
			t.Errorf("activity %d = %+v", id, *a)
		}
	}
	if tot := tr.Totals(); tot != (Totals{Built: 0, BuildsExpected: 2, Fetched: 0, FetchesExpected: 1}) {
		t.Errorf("totals = %+v", tot)
	}
	// stop removes; results for unknown ids are ignored.
	tr.Apply(Event{Action: "stop", ID: 135})
	tr.Apply(Event{Action: "result", ID: 135, Type: ResBuildLogLine})
	if len(tr.Snapshot()) != 6 || find(tr.Snapshot(), 135) != nil {
		t.Error("stop did not remove the build")
	}
}

func TestStoreName(t *testing.T) {
	cases := map[string]string{
		"/nix/store/150zykpi9v1hhm87yf1y1b3ail40s36w-nginx-1.27.3.drv":                        "nginx-1.27.3",
		"/nix/store/wl6xbyf0k5b14izm59rfh9rvdyjh4n68-nyancat-1.5.2":                           "nyancat-1.5.2",
		"/nix/store/hjvdx1nqrjy9fa4lmafxkph1sam2rxf0-nixos-system-pi3-26.05.20260825.f4f6986": "nixos-system-pi3-26.05.20260825.f4f6986",
		"not-a-store-path": "not-a-store-path",
		"":                 ".",
	}
	for in, want := range cases {
		if got := StoreName(in); got != want {
			t.Errorf("StoreName(%q) = %q, want %q", in, got, want)
		}
	}
}

func TestHumanSize(t *testing.T) {
	if got := HumanSize(12_400_000, 45_000_000); got != "12.4/45.0 MB" {
		t.Errorf("got %q", got)
	}
	if got := HumanSize(4125, 15909); got != "4.1/15.9 KB" {
		t.Errorf("got %q", got)
	}
}

func TestDrvOutputs(t *testing.T) {
	zlib := `Derive([("dev","/nix/store/hw7cncb19aszv26k2wnd14mwg5anqns7-zlib-1.3.2-dev","",""),("out","/nix/store/0d2236qcwl1bi900c59h9rkd2ls58f9a-zlib-1.3.2","",""),("static","/nix/store/vldmg1y5yxvvkd2bnd1xamy1bdc2js3y-zlib-1.3.2-static","","")],[("/nix/store/akag406i2x9yrv04yz1ydq9hnh63pkks-zlib-1.3.2.tar.gz.drv",["out"])],...`
	got := drvOutputs([]byte(zlib))
	want := []string{
		"/nix/store/hw7cncb19aszv26k2wnd14mwg5anqns7-zlib-1.3.2-dev",
		"/nix/store/0d2236qcwl1bi900c59h9rkd2ls58f9a-zlib-1.3.2",
		"/nix/store/vldmg1y5yxvvkd2bnd1xamy1bdc2js3y-zlib-1.3.2-static",
	}
	if strings.Join(got, ",") != strings.Join(want, ",") {
		t.Errorf("drvOutputs = %v, want %v", got, want)
	}
	// Input derivations after the outputs list must not leak in.
	if len(drvOutputs([]byte(`Derive([("out","","","")],[("/nix/store/x.drv",["out"])],...`))) != 0 {
		t.Error("content-addressed (empty) output or input drv leaked into outputs")
	}
	if drvOutputs([]byte("not a drv")) != nil {
		t.Error("garbage parsed as a drv")
	}
}
