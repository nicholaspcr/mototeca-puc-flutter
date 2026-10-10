package vehicle

import (
	"context"
	"errors"
)

var (
	ErrDuplicatePlate  = errors.New("plate already registered")
	ErrDuplicateChassi = errors.New("chassi already registered")
)

// Store is what Handler needs; tests use an in-memory fake.
type Store interface {
	// FindByPlate returns nil, nil when the plate has no history yet.
	FindByPlate(ctx context.Context, plate string) (*Vehicle, error)
	// Create returns ErrDuplicatePlate or ErrDuplicateChassi for a vehicle
	// that is already registered.
	Create(ctx context.Context, input CreateInput) (*Vehicle, error)
}

var _ Store = (*Repository)(nil)
