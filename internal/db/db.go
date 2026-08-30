// Package db wires up the Postgres connection pool.
package db

import (
	"context"
	"fmt"

	"github.com/exaring/otelpgx"
	"github.com/jackc/pgx/v5/pgxpool"
)

// NewPool opens a connection pool to dsn, instrumented with an OpenTelemetry
// query tracer so queries show up as spans under whatever span is active in
// the caller's context (a no-op when tracing isn't configured).
func NewPool(ctx context.Context, dsn string) (*pgxpool.Pool, error) {
	cfg, err := pgxpool.ParseConfig(dsn)
	if err != nil {
		return nil, fmt.Errorf("parsing database url: %w", err)
	}
	cfg.ConnConfig.Tracer = otelpgx.NewTracer()

	return pgxpool.NewWithConfig(ctx, cfg)
}
