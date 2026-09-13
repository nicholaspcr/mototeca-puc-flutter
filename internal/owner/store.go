package owner

import (
	"context"
	"errors"
)

var (
	// ErrDuplicatePhone is returned by Create when the phone is taken.
	ErrDuplicatePhone = errors.New("phone already registered")
	// ErrVehicleNotFound is returned by Claim when no vehicle has that plate.
	ErrVehicleNotFound = errors.New("vehicle not found")
	// ErrVehicleClaimed is returned by Claim when someone else owns it.
	ErrVehicleClaimed = errors.New("vehicle already claimed")
)

// Store is the storage contract Handler depends on. Repository is the
// Postgres-backed implementation; tests substitute an in-memory fake.
type Store interface {
	// FindByPhone returns nil, nil when nobody is registered under it.
	FindByPhone(ctx context.Context, phone string) (*Owner, error)
	Create(ctx context.Context, input CreateInput, passwordHash string) (*Owner, error)
	// ListVehicles returns the owner's bikes, with the figures derived from
	// their service history.
	ListVehicles(ctx context.Context, ownerID string) ([]OwnedVehicle, error)
	// Claim links a vehicle to an owner. Claiming a bike already linked to
	// that same owner succeeds, so the action is idempotent.
	Claim(ctx context.Context, ownerID, plate string) (*OwnedVehicle, error)
	// Release unlinks a bike the owner holds, leaving its history intact.
	Release(ctx context.Context, ownerID, plate string) error
}

var _ Store = (*Repository)(nil)
