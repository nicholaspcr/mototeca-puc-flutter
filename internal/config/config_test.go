package config

import (
	"strings"
	"testing"
	"time"
)

// testSecret is long enough to satisfy auth.MinSecretLength.
const testSecret = "test-auth-secret-that-is-long-enough"

// setRequired sets everything Load insists on, so each subtest only has to
// vary the one field it is about.
func setRequired(t *testing.T) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://localhost/test")
	t.Setenv("AUTH_SECRET", testSecret)
}

func TestLoad(t *testing.T) {
	t.Run("missing database url", func(t *testing.T) {
		setRequired(t)
		t.Setenv("DATABASE_URL", "")
		if _, err := Load(); err == nil {
			t.Fatal("expected error for missing DATABASE_URL, got nil")
		}
	})

	t.Run("missing auth secret", func(t *testing.T) {
		setRequired(t)
		t.Setenv("AUTH_SECRET", "")
		if _, err := Load(); err == nil {
			t.Fatal("expected error for missing AUTH_SECRET, got nil")
		}
	})

	t.Run("short auth secret", func(t *testing.T) {
		setRequired(t)
		t.Setenv("AUTH_SECRET", strings.Repeat("a", 8))
		if _, err := Load(); err == nil {
			t.Fatal("expected error for a too-short AUTH_SECRET, got nil")
		}
	})

	t.Run("defaults", func(t *testing.T) {
		setRequired(t)
		t.Setenv("PORT", "")
		t.Setenv("LOG_FORMAT", "")
		t.Setenv("OTEL_EXPORTER", "")

		cfg, err := Load()
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if cfg.Port != "8080" {
			t.Errorf("Port = %q, want default 8080", cfg.Port)
		}
		if cfg.LogFormat != "text" {
			t.Errorf("LogFormat = %q, want default text", cfg.LogFormat)
		}
		if cfg.OTelExporter != "none" {
			t.Errorf("OTelExporter = %q, want default none", cfg.OTelExporter)
		}
		if cfg.AuthTokenTTL <= 0 || cfg.AuthTokenTTL > 24*time.Hour {
			t.Errorf("AuthTokenTTL = %v, want a positive TTL of at most a day", cfg.AuthTokenTTL)
		}
	})

	t.Run("invalid log format", func(t *testing.T) {
		setRequired(t)
		t.Setenv("LOG_FORMAT", "xml")
		if _, err := Load(); err == nil {
			t.Fatal("expected error for invalid LOG_FORMAT, got nil")
		}
	})

	t.Run("invalid otel exporter", func(t *testing.T) {
		setRequired(t)
		t.Setenv("OTEL_EXPORTER", "carrier-pigeon")
		if _, err := Load(); err == nil {
			t.Fatal("expected error for invalid OTEL_EXPORTER, got nil")
		}
	})
}
