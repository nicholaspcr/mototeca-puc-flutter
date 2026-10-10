// Package logging constructs the application's structured logger.
package logging

import (
	"io"
	"log/slog"
	"os"
)

// New returns a stdout logger: JSON when format is "json", text otherwise.
func New(format string) *slog.Logger {
	return NewWithWriter(format, os.Stdout)
}

// NewWithWriter is like New but writes to w instead of stdout, so callers
// (and tests) can inspect the output.
func NewWithWriter(format string, w io.Writer) *slog.Logger {
	opts := &slog.HandlerOptions{Level: slog.LevelInfo}

	var handler slog.Handler
	if format == "json" {
		handler = slog.NewJSONHandler(w, opts)
	} else {
		handler = slog.NewTextHandler(w, opts)
	}

	return slog.New(handler)
}
