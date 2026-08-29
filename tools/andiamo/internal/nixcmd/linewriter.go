package nixcmd

import "bytes"

// LineWriter splits a child's stderr into lines as they arrive and
// hands each to Fn. It is installed as cmd.Stderr (exec owns the pipe
// and copy goroutine, so Output/Wait and WaitDelay keep working)
// rather than read through StderrPipe, where Wait closes the pipe
// under the reader, and a bufio.Scanner would choke on a >64 KiB
// line. Fn runs on exec's copy goroutine.
type LineWriter struct {
	Fn   func(string)
	tail []byte
}

func (w *LineWriter) Write(p []byte) (int, error) {
	w.tail = append(w.tail, p...)
	for {
		i := bytes.IndexByte(w.tail, '\n')
		if i < 0 {
			break
		}
		w.Fn(string(w.tail[:i]))
		w.tail = w.tail[i+1:]
	}
	return len(p), nil
}

// Flush emits a trailing partial line; call once the child has exited.
func (w *LineWriter) Flush() {
	if len(w.tail) > 0 {
		w.Fn(string(w.tail))
		w.tail = nil
	}
}
