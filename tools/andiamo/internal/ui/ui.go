// Package ui renders andiamo's terminal output: colored status tables
// on stdout and a live per-host progress display on stderr. Colour
// degrades to plain text when stdout isn't a TTY; progress degrades to
// one log line per phase change when stderr isn't.
package ui

import (
	"fmt"
	"os"
	"regexp"
	"strings"
	"sync"
	"time"
	"unicode/utf8"
)

var (
	colorEnabled = false
	liveEnabled  = false
)

// Init decides whether color and live output are used. Colour follows
// stdout (that's where the tables go); live redraw follows stderr
// (that's where progress goes), so `status -json | jq` gets clean
// JSON and a spinner, and `2>/dev/null` gets neither.
func Init(noColor bool) {
	colorEnabled = !noColor && os.Getenv("NO_COLOR") == "" && IsTTY(os.Stdout)
	liveEnabled = colorEnabled && IsTTY(os.Stderr)
}

func paint(code, s string) string {
	if !colorEnabled {
		return s
	}
	return "\x1b[" + code + "m" + s + "\x1b[0m"
}

func Green(s string) string  { return paint("32", s) }
func Yellow(s string) string { return paint("33", s) }
func Red(s string) string    { return paint("31", s) }
func Dim(s string) string    { return paint("2", s) }
func Bold(s string) string   { return paint("1", s) }

// ShortPath abbreviates a store path to the first 8 characters of its
// hash, or "-" when empty.
func ShortPath(p string) string {
	base := strings.TrimPrefix(p, "/nix/store/")
	if base == p || len(base) < 8 {
		if p == "" {
			return "-"
		}
		return p
	}
	return base[:8]
}

// escRE matches one escape: a CSI sequence (ESC [ … final byte), an
// OSC sequence (ESC ] … BEL), or a lone ESC byte.
var escRE = regexp.MustCompile("\x1b(?:\\[[0-9;?]*[ -/]*[@-~]|\\][^\x07]*\x07)?")

// Scrub makes one line of child output safe to embed in a dim detail
// on the live display. Tabs become spaces. Colour (SGR) sequences are
// kept when colour is on — nixos test drivers and compilers colour
// their output, and it's worth seeing — but a reset inside them would
// end the row's dim early, so every reset re-asserts dim. Every other
// escape sequence (cursor movement, erase, OSC) and stray ESC byte is
// dropped: those would wreck the redraw.
func Scrub(s string) string {
	s = strings.ReplaceAll(s, "\t", " ")
	return escRE.ReplaceAllStringFunc(s, func(seq string) string {
		switch {
		case !colorEnabled || !strings.HasPrefix(seq, "\x1b[") || !strings.HasSuffix(seq, "m"):
			return ""
		case seq == "\x1b[m" || seq == "\x1b[0m":
			return "\x1b[0m\x1b[2m"
		}
		return seq
	})
}

// Truncate cuts s to at most max visible cells. ANSI colour sequences
// pass through uncounted, and a reset is appended if the cut landed
// inside a coloured span, so a truncated line can't bleed colour into
// the next one.
func Truncate(s string, max int) string {
	if Width(s) <= max {
		return s
	}
	var b strings.Builder
	cells := 0
	coloured := false
	for i := 0; i < len(s) && cells < max; {
		if s[i] == '\x1b' {
			if loc := ansiRE.FindStringIndex(s[i:]); loc != nil && loc[0] == 0 {
				seq := s[i : i+loc[1]]
				b.WriteString(seq)
				coloured = seq != "\x1b[0m"
				i += loc[1]
				continue
			}
		}
		_, n := utf8.DecodeRuneInString(s[i:])
		b.WriteString(s[i : i+n])
		cells++
		i += n
	}
	if coloured {
		b.WriteString("\x1b[0m")
	}
	return b.String()
}

var spinnerFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

type row struct {
	phase   string
	detail  string // what the phase is doing right now; live only
	done    bool
	ok      bool
	result  string
	started time.Time
	elapsed time.Duration
}

// Progress is a live multi-line display on stderr, one line per host.
// When stderr is not a TTY it falls back to printing one log line per
// phase change.
type Progress struct {
	mu      sync.Mutex
	order   []string
	rows    map[string]*row
	live    bool
	printed int
	frame   int
	stop    chan struct{}
	wg      sync.WaitGroup
}

func NewProgress(hosts []string) *Progress {
	p := &Progress{
		order: hosts,
		rows:  make(map[string]*row, len(hosts)),
		live:  liveEnabled,
		stop:  make(chan struct{}),
	}
	for _, h := range hosts {
		p.rows[h] = &row{phase: "queued", started: time.Now()}
	}
	if p.live {
		p.wg.Add(1)
		go p.loop()
	}
	return p
}

func (p *Progress) loop() {
	defer p.wg.Done()
	tick := time.NewTicker(120 * time.Millisecond)
	defer tick.Stop()
	for {
		select {
		case <-tick.C:
			p.mu.Lock()
			p.frame++
			p.render()
			p.mu.Unlock()
		case <-p.stop:
			p.mu.Lock()
			p.render()
			p.mu.Unlock()
			return
		}
	}
}

// Set updates a host's phase.
func (p *Progress) Set(host, phase string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	r := p.rows[host]
	if r == nil || r.done {
		return
	}
	if r.phase == "queued" {
		r.started = time.Now()
	}
	r.phase = phase
	if !p.live {
		fmt.Fprintf(os.Stderr, "%s: %s\n", host, phase)
	}
}

// Detail sets what a host's current phase is doing (a file being
// evaluated, a derivation being built). It only ever shows on the
// live display: callers send thousands of these, and the non-live log
// stays phase changes only.
func (p *Progress) Detail(host, text string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	r := p.rows[host]
	if r == nil || r.done {
		return
	}
	r.detail = text
}

// Done marks a host finished.
func (p *Progress) Done(host string, ok bool, result string) {
	p.mu.Lock()
	defer p.mu.Unlock()
	r := p.rows[host]
	if r == nil {
		return
	}
	r.done = true
	r.ok = ok
	r.result = result
	r.detail = ""
	r.elapsed = time.Since(r.started).Round(time.Second)
	if !p.live {
		mark := "ok"
		if !ok {
			mark = "FAILED"
		}
		fmt.Fprintf(os.Stderr, "%s: %s (%s, %s)\n", host, result, mark, r.elapsed)
	}
}

// Close stops the render loop, leaving the final state on screen.
func (p *Progress) Close() {
	if p.live {
		close(p.stop)
		p.wg.Wait()
	}
}

// render assumes p.mu is held. Every line is cut to the terminal
// width minus one: the detail is the only part that can grow, and it
// sits last, so truncation eats the path rather than the timer — and
// a line never wraps (which would break the cursor-up redraw) or
// lands exactly on the last column (where some terminals defer the
// wrap and double the line anyway).
func (p *Progress) render() {
	var b strings.Builder
	if p.printed > 0 {
		fmt.Fprintf(&b, "\x1b[%dA", p.printed)
	}
	cols := termWidth(os.Stderr)
	width := 0
	for _, h := range p.order {
		if len(h) > width {
			width = len(h)
		}
	}
	for _, h := range p.order {
		r := p.rows[h]
		var mark, text string
		switch {
		case r.done && r.ok:
			mark = Green("✓")
			text = fmt.Sprintf("%s  %s", r.result, Dim(r.elapsed.String()))
		case r.done:
			mark = Red("✗")
			text = fmt.Sprintf("%s  %s", Red(r.result), Dim(r.elapsed.String()))
		case r.phase == "queued":
			mark = Dim("·")
			text = Dim(r.phase)
		default:
			mark = Yellow(spinnerFrames[p.frame%len(spinnerFrames)])
			text = fmt.Sprintf("%s  %s", r.phase, Dim(time.Since(r.started).Round(time.Second).String()))
			if r.detail != "" {
				text += "  " + Dim(r.detail)
			}
		}
		line := fmt.Sprintf("%s %-*s  %s", mark, width, h, text)
		b.WriteString("\x1b[2K" + Truncate(line, cols-1) + "\n")
	}
	p.printed = len(p.order)
	fmt.Fprint(os.Stderr, b.String())
}
