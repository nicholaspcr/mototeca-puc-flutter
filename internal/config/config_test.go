package config

import "testing"

func TestLoad(t *testing.T) {
	t.Run("missing database url", func(t *testing.T) {
		t.Setenv("DATABASE_URL", "")
		if _, err := Load(); err == nil {
			t.Fatal("expected error for missing DATABASE_URL, got nil")
		}
	})

	t.Run("defaults", func(t *testing.T) {
		t.Setenv("DATABASE_URL", "postgres://localhost/test")
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
	})

	t.Run("invalid log format", func(t *testing.T) {
		t.Setenv("DATABASE_URL", "postgres://localhost/test")
		t.Setenv("LOG_FORMAT", "xml")
		if _, err := Load(); err == nil {
			t.Fatal("expected error for invalid LOG_FORMAT, got nil")
		}
	})

	t.Run("invalid otel exporter", func(t *testing.T) {
		t.Setenv("DATABASE_URL", "postgres://localhost/test")
		t.Setenv("OTEL_EXPORTER", "carrier-pigeon")
		if _, err := Load(); err == nil {
			t.Fatal("expected error for invalid OTEL_EXPORTER, got nil")
		}
	})
}
