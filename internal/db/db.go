// Package db wires up the Postgres connection pool.
package db

import (
	"context"
	"fmt"

	"github.com/exaring/otelpgx"
	"github.com/jackc/pgx/v5/pgxpool"
)

// NewPool opens a pgx pool traced with OpenTelemetry.
func NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parsing database url: %w", err)
	}
	cfg.ConnConfig.Tracer = otelpgx.NewTracer()

	return pgxpool.NewWithConfig(ctx, cfg)
}
