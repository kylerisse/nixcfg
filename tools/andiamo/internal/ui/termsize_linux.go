//go:build linux

package ui

import (
	"os"
	"strconv"
	"syscall"
	"unsafe"
)

type winsize struct {
	Row, Col, Xpixel, Ypixel uint16
}

// getWinsize asks the terminal behind f for its size. The ioctl only
// succeeds on a terminal, which is what makes it the right isatty
// test: /dev/null is a character device too, but not a terminal.
func getWinsize(f *os.File) (winsize, bool) {
	var ws winsize
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), syscall.TIOCGWINSZ, uintptr(unsafe.Pointer(&ws)))
	return ws, errno == 0
}

// IsTTY reports whether f is a terminal.
func IsTTY(f *os.File) bool {
	_, ok := getWinsize(f)
	return ok
}

// termWidth is the column count of f's terminal, falling back to
// $COLUMNS and then 80. Queried per render tick rather than via
// SIGWINCH: it's one cheap ioctl, and a resize between ticks costs at
// most one misdrawn frame.
func termWidth(f *os.File) int {
	if ws, ok := getWinsize(f); ok && ws.Col > 0 {
		return int(ws.Col)
	}
	if n, err := strconv.Atoi(os.Getenv("COLUMNS")); err == nil && n > 0 {
		return n
	}
	return 80
}
