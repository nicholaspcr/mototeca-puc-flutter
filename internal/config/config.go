// Package config loads and validates the API's environment-based
// configuration in one place, instead of scattering os.Getenv calls.
package config

import (
	"fmt"
	"os"
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
}

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

	return cfg, nil
}
