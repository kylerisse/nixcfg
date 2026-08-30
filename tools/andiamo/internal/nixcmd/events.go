package nixcmd

import (
	"encoding/json"
	"path"
	"sort"
	"strconv"
	"strings"
	"sync"
)

// Activity and result types of nix's --log-format internal-json
// stream (nix/src/libutil/logging.hh). Only the ones andiamo reads.
const (
	ActCopyPath      = 100 // fields: storePath, from, to
	ActFileTransfer  = 101 // fields: uri; progress in bytes
	ActRealise       = 102
	ActCopyPaths     = 103 // progress: fetched, expected
	ActBuilds        = 104 // progress: built, expected
	ActBuild         = 105 // fields: drvPath, machine, round, nrRounds
	ActSubstitute    = 108 // fields: storePath, substituter
	ActQueryPathInfo = 109 // fields: storePath, substituter

	ResBuildLogLine = 101 // fields: line
	ResSetPhase     = 104 // fields: phase
	ResProgress     = 105 // fields: done, expected, running, failed
)

// Event is one "@nix {…}" line. start events open an activity (ID,
// Parent, Type, Text, Fields), result events attach to one (ID, Type,
// Fields), stop events close it, and msg events are free-standing
// log lines (Level 0 = error, 1 = warning).
type Event struct {
	Action string            `json:"action"`
	ID     uint64            `json:"id"`
	Parent uint64            `json:"parent"`
	Type   int               `json:"type"`
	Level  int               `json:"level"`
	Text   string            `json:"text"`
	Msg    string            `json:"msg"`
	Fields []json.RawMessage `json:"fields"`
}

func (e Event) str(i int) string {
	var s string
	if i < len(e.Fields) {
		_ = json.Unmarshal(e.Fields[i], &s)
	}
	return s
}

func (e Event) num(i int) int64 {
	var n int64
	if i < len(e.Fields) {
		_ = json.Unmarshal(e.Fields[i], &n)
	}
	return n
}

// Activity is a live nix activity as far as andiamo cares: what path
// it's about and how it's going.
type Activity struct {
	ID, Parent uint64
	Type       int
	Path       string // the .drv or store path it concerns, if any
	Text       string
	Seq        uint64 // start order; higher is newer
	Phase      string // build phase (unpackPhase, buildPhase, …)
	LastLine   string // last build log line
	Done       int64  // own progress
	Expected   int64
	Bytes      int64 // transfer progress rolled up from file transfers beneath
	BytesTotal int64
}

// Totals are the build's fleet-wide counters, from the root builds
// and copy-paths activities.
type Totals struct {
	Built, BuildsExpected    int64
	Fetched, FetchesExpected int64
}

// Tracker folds the event stream into the set of live activities.
// Apply is safe to call from the child's copy goroutine while
// Snapshot/Totals are read from a render loop.
type Tracker struct {
	mu     sync.Mutex
	seq    uint64
	live   map[uint64]*Activity
	totals Totals
}

func (t *Tracker) Apply(e Event) {
	t.mu.Lock()
	defer t.mu.Unlock()
	if t.live == nil {
		t.live = map[uint64]*Activity{}
	}
	switch e.Action {
	case "start":
		t.seq++
		a := &Activity{ID: e.ID, Parent: e.Parent, Type: e.Type, Text: e.Text, Seq: t.seq}
		switch e.Type {
		case ActBuild, ActSubstitute, ActCopyPath, ActQueryPathInfo:
			a.Path = e.str(0)
		}
		t.live[e.ID] = a
	case "stop":
		delete(t.live, e.ID)
	case "result":
		a := t.live[e.ID]
		if a == nil {
			return
		}
		switch e.Type {
		case ResBuildLogLine:
			a.LastLine = e.str(0)
		case ResSetPhase:
			a.Phase = e.str(0)
		case ResProgress:
			a.Done, a.Expected = e.num(0), e.num(1)
			switch a.Type {
			case ActBuilds:
				t.totals.Built, t.totals.BuildsExpected = a.Done, a.Expected
			case ActCopyPaths:
				t.totals.Fetched, t.totals.FetchesExpected = a.Done, a.Expected
			case ActFileTransfer:
				// A download sits under the copy-path under the
				// substitute; the bytes are what the operator is
				// waiting on, so surface them on both.
				for p := t.live[a.Parent]; p != nil; p = t.live[p.Parent] {
					if p.Type == ActCopyPath || p.Type == ActSubstitute {
						p.Bytes, p.BytesTotal = a.Done, a.Expected
					}
				}
			}
		}
	}
}

// Snapshot returns the live activities, newest first.
func (t *Tracker) Snapshot() []Activity {
	t.mu.Lock()
	defer t.mu.Unlock()
	out := make([]Activity, 0, len(t.live))
	for _, a := range t.live {
		out = append(out, *a)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Seq > out[j].Seq })
	return out
}

func (t *Tracker) Totals() Totals {
	t.mu.Lock()
	defer t.mu.Unlock()
	return t.totals
}

// StoreName strips a store path to its package name:
// /nix/store/<hash>-nginx-1.27.3.drv → nginx-1.27.3.
func StoreName(p string) string {
	base := path.Base(strings.TrimSuffix(p, ".drv"))
	if i := strings.IndexByte(base, '-'); i == 32 {
		return base[i+1:]
	}
	return base
}

// HumanSize renders a transfer as "12.4/45.0 MB" (KB below a megabyte).
func HumanSize(done, total int64) string {
	unit, div := "MB", 1e6
	if total < 1e6 {
		unit, div = "KB", 1e3
	}
	f := func(n int64) string { return strconv.FormatFloat(float64(n)/div, 'f', 1, 64) }
	return f(done) + "/" + f(total) + " " + unit
}
