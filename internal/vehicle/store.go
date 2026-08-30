package vehicle

import "context"

// Store is the storage contract Handler depends on. Repository is the
// Postgres-backed implementation; tests substitute an in-memory fake instead
// of standing up a real database.
type Store interface {
	// FindByPlate returns nil, nil when the plate has no history yet.
	FindByPlate(ctx context.Context, plate string) (*Vehicle, error)
	Create(ctx context.Context, input CreateInput) (*Vehicle, error)
}

var _ Store = (*Repository)(nil)
