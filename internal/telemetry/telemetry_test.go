package telemetry

import (
	"context"
	"testing"
	"time"
)

func TestSetupNoneIsNoop(t *testing.T) {
	shutdown, err := Setup(context.Background(), "none", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	if err := shutdown(context.Background()); err != nil {
		t.Errorf("shutdown: %v", err)
	}
}

func TestSetupUnknownExporter(t *testing.T) {
	if _, err := Setup(context.Background(), "carrier-pigeon", ""); err == nil {
		t.Fatal("expected error for unknown exporter, got nil")
	}
}

func TestSetupStdout(t *testing.T) {
	shutdown, err := Setup(context.Background(), "stdout", "")
	if err != nil {
		t.Fatalf("unexpected error: %v", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()
	if err := shutdown(ctx); err != nil {
		t.Errorf("shutdown: %v", err)
	}
}
