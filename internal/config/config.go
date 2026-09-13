// Package config loads and validates the API's environment-based
// configuration in one place, instead of scattering os.Getenv calls.
package config

import (
	"fmt"
	"os"
	"strings"
	"time"

	"mototeca-backend/internal/auth"
)

// defaultAuthTokenTTL keeps a stolen token useful for hours, not weeks.
const defaultAuthTokenTTL = 12 * time.Hour

// Config holds the API's runtime configuration.
type Config struct {
	// DatabaseURL is the Postgres connection string. Required.
	DatabaseURL string
	// Port is the TCP port the HTTP server listens on. Defaults to 8080.
	Port string
	// LogFormat selects the slog handler: "text" (default, for local dev)
	// or "json" (for production log aggregation).
	LogFormat string
	// OTelExporter selects the tracing exporter: "none" (default, tracing
	// disabled), "stdout", or "otlp".
	OTelExporter string
	// OTelEndpoint is the OTLP collector endpoint, used when
	// OTelExporter == "otlp". Empty uses the exporter's own default.
	OTelEndpoint string
	// AuthSecret signs workshop session tokens. Required, and never defaulted:
	// a fallback key would silently make every deployment forgeable.
	AuthSecret string
	// AuthTokenTTL is how long a workshop session stays valid. Tokens are
	// self-contained and cannot be revoked early, so this is kept short.
	AuthTokenTTL time.Duration
	// Storage holds the object-storage settings for service photos. Empty
	// StorageEndpoint disables uploads rather than failing to start, so the
	// rest of the API runs without object storage available.
	StorageEndpoint  string
	StorageAccessKey string
	StorageSecretKey string
	StorageBucket    string
	StoragePublicURL string
	StorageUseSSL    bool
	// CORSAllowedOrigins are the browser origins allowed to call the API.
	// Empty allows loopback origins only, for the Flutter web dev server.
	CORSAllowedOrigins []string
}

// StorageEnabled reports whether photo uploads are configured.
func (c Config) StorageEnabled() bool { return c.StorageEndpoint != "" }

// Load reads Config from the environment and validates required fields.
func Load() (Config, error) {
	cfg := Config{
		DatabaseURL:  os.Getenv("DATABASE_URL"),
		Port:         os.Getenv("PORT"),
		LogFormat:    os.Getenv("LOG_FORMAT"),
		OTelExporter: os.Getenv("OTEL_EXPORTER"),
		OTelEndpoint: os.Getenv("OTEL_EXPORTER_OTLP_ENDPOINT"),
		AuthSecret:   os.Getenv("AUTH_SECRET"),
		AuthTokenTTL: defaultAuthTokenTTL,

		StorageEndpoint:  os.Getenv("STORAGE_ENDPOINT"),
		StorageAccessKey: os.Getenv("STORAGE_ACCESS_KEY"),
		StorageSecretKey: os.Getenv("STORAGE_SECRET_KEY"),
		StorageBucket:    os.Getenv("STORAGE_BUCKET"),
		StoragePublicURL: os.Getenv("STORAGE_PUBLIC_URL"),
		StorageUseSSL:    os.Getenv("STORAGE_USE_SSL") == "true",

		CORSAllowedOrigins: splitList(os.Getenv("CORS_ALLOWED_ORIGINS")),
	}

	if cfg.DatabaseURL == "" {
		return Config{}, fmt.Errorf("DATABASE_URL not configured")
	}
	if len(cfg.AuthSecret) < auth.MinSecretLength {
		return Config{}, fmt.Errorf("AUTH_SECRET must be set to at least %d characters", auth.MinSecretLength)
	}
	if cfg.Port == "" {
		cfg.Port = "8080"
	}
	if cfg.LogFormat == "" {
		cfg.LogFormat = "text"
	}
	if cfg.LogFormat != "text" && cfg.LogFormat != "json" {
		return Config{}, fmt.Errorf("LOG_FORMAT must be \"text\" or \"json\", got %q", cfg.LogFormat)
	}
	if cfg.OTelExporter == "" {
		cfg.OTelExporter = "none"
	}
	if cfg.OTelExporter != "none" && cfg.OTelExporter != "stdout" && cfg.OTelExporter != "otlp" {
		return Config{}, fmt.Errorf("OTEL_EXPORTER must be \"none\", \"stdout\", or \"otlp\", got %q", cfg.OTelExporter)
	}

	if cfg.StorageEnabled() {
		if cfg.StorageAccessKey == "" || cfg.StorageSecretKey == "" || cfg.StorageBucket == "" {
			return Config{}, fmt.Errorf("STORAGE_ACCESS_KEY, STORAGE_SECRET_KEY and STORAGE_BUCKET are required when STORAGE_ENDPOINT is set")
		}
		if cfg.StoragePublicURL == "" {
			return Config{}, fmt.Errorf("STORAGE_PUBLIC_URL is required when STORAGE_ENDPOINT is set")
		}
	}

	return cfg, nil
}

func splitList(raw string) []string {
	var items []string
	for item := range strings.SplitSeq(raw, ",") {
		if trimmed := strings.TrimSpace(item); trimmed != "" {
			items = append(items, trimmed)
		}
	}
	return items
}
