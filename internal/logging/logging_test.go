package logging

import (
	"bytes"
	"encoding/json"
	"strings"
	"testing"
)

func TestNewWithWriterJSON(t *testing.T) {
	var buf bytes.Buffer
	NewWithWriter("json", &buf).Info("hello", "k", "v")

	var decoded map[string]any
	if err := json.Unmarshal(buf.Bytes(), &decoded); err != nil {
		t.Fatalf("expected valid JSON output, got error: %v (output: %q)", err, buf.String())
	}
	if decoded["msg"] != "hello" {
		t.Errorf("msg = %v, want %q", decoded["msg"], "hello")
	}
	if decoded["k"] != "v" {
		t.Errorf("k = %v, want %q", decoded["k"], "v")
	}
}

func TestNewWithWriterText(t *testing.T) {
	for _, format := range []string{"text", "", "anything-else"} {
		var buf bytes.Buffer
		NewWithWriter(format, &buf).Info("hello", "k", "v")

		if !strings.Contains(buf.String(), "msg=hello") {
			t.Errorf("format %q: expected text output to contain msg=hello, got %q", format, buf.String())
		}
	}
}
