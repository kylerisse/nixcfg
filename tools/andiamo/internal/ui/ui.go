// Package ui renders andiamo's terminal output: colored status tables
// and a live per-host progress display during deploys. Everything
// degrades to plain sequential lines when stdout isn't a TTY.
package ui

import (
	"fmt"
	"os"
	"strings"
	"sync"
	"time"
)

var colorEnabled = false

// Init decides whether color/live output is used.
func Init(noColor bool) {
	colorEnabled = !noColor && os.Getenv("NO_COLOR") == "" && IsTTY(os.Stdout)
}

// Live reports whether rich terminal output (color, live redraw,
// nix's own progress bar) is active.
func Live() bool { return colorEnabled }

// IsTTY reports whether f is a character device.
func IsTTY(f *os.File) bool {
	fi, err := f.Stat()
	if err != nil {
		return false
	}
	return fi.Mode()&os.ModeCharDevice != 0
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

// Age renders an epoch as a short relative age ("5m", "3h", "12d"),
// or "-" for zero/future values.
func Age(epoch int64) string {
	if epoch <= 0 {
		return "-"
	}
	d := time.Since(time.Unix(epoch, 0))
	switch {
	case d < 0:
		return "-"
	case d < 90*time.Minute:
		return fmt.Sprintf("%dm", int(d.Minutes()))
	case d < 36*time.Hour:
		return fmt.Sprintf("%dh", int(d.Hours()))
	default:
		return fmt.Sprintf("%dd", int(d.Hours()/24))
	}
}

var spinnerFrames = []string{"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}

type row struct {
	phase   string
	done    bool
	ok      bool
	result  string
	started time.Time
	elapsed time.Duration
}

// Progress is a live multi-line display, one line per host. When
// stdout is not a TTY it falls back to printing one log line per
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
		live:  colorEnabled,
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
	r.phase = phase
	if !p.live {
		fmt.Printf("%s: %s\n", host, phase)
	}
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
	r.elapsed = time.Since(r.started).Round(time.Second)
	if !p.live {
		mark := "ok"
		if !ok {
			mark = "FAILED"
		}
		fmt.Printf("%s: %s (%s, %s)\n", host, result, mark, r.elapsed)
	}
}

// Close stops the render loop, leaving the final state on screen.
func (p *Progress) Close() {
	if p.live {
		close(p.stop)
		p.wg.Wait()
	}
}

// render assumes p.mu is held.
func (p *Progress) render() {
	var b strings.Builder
	if p.printed > 0 {
		fmt.Fprintf(&b, "\x1b[%dA", p.printed)
	}
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
		}
		fmt.Fprintf(&b, "\x1b[2K%s %-*s  %s\n", mark, width, h, text)
	}
	p.printed = len(p.order)
	fmt.Print(b.String())
}
