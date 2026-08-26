package ui

import (
	"regexp"
	"strings"
	"unicode/utf8"
)

var ansiRE = regexp.MustCompile("\x1b\\[[0-9;]*m")

// Width is the visible width of s: ANSI colour sequences are ignored
// and every remaining rune counts as one cell. That is exact for the
// ASCII and single-width glyphs (✓ ↻ ⌂ →) andiamo prints; it is not a
// general East-Asian-width implementation.
func Width(s string) int {
	return utf8.RuneCountInString(ansiRE.ReplaceAllString(s, ""))
}

// Table renders rows as content-sized columns separated by two
// spaces. Cells may carry colour; alignment is computed on visible
// width, so painting a cell never shifts its neighbours. The last
// column is left ragged and trailing whitespace is dropped, so rows
// with an empty final cell end cleanly. Returns "" for no rows.
func Table(rows [][]string) string {
	cols := 0
	for _, r := range rows {
		if len(r) > cols {
			cols = len(r)
		}
	}
	if cols == 0 {
		return ""
	}
	width := make([]int, cols)
	for _, r := range rows {
		for i, c := range r {
			if w := Width(c); w > width[i] {
				width[i] = w
			}
		}
	}
	var b strings.Builder
	for _, r := range rows {
		var line strings.Builder
		for i := 0; i < cols; i++ {
			c := ""
			if i < len(r) {
				c = r[i]
			}
			if i > 0 {
				line.WriteString("  ")
			}
			line.WriteString(c)
			if i < cols-1 {
				line.WriteString(strings.Repeat(" ", width[i]-Width(c)))
			}
		}
		b.WriteString(strings.TrimRight(line.String(), " "))
		b.WriteByte('\n')
	}
	return b.String()
}
