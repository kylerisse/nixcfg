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

// termWidth is the column count of f's terminal, falling back to
// $COLUMNS and then 80. Queried per render tick rather than via
// SIGWINCH: it's one cheap ioctl, and a resize between ticks costs at
// most one misdrawn frame.
func termWidth(f *os.File) int {
	var ws winsize
	_, _, errno := syscall.Syscall(syscall.SYS_IOCTL, f.Fd(), syscall.TIOCGWINSZ, uintptr(unsafe.Pointer(&ws)))
	if errno == 0 && ws.Col > 0 {
		return int(ws.Col)
	}
	if n, err := strconv.Atoi(os.Getenv("COLUMNS")); err == nil && n > 0 {
		return n
	}
	return 80
}
