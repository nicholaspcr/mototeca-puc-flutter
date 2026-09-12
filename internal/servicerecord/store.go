package servicerecord

import (
	"context"
	"errors"
	"time"
)

// ErrVehicleNotFound is returned by Create when the plate has no vehicle yet.
// Registering the bike is a separate, deliberate step.
var ErrVehicleNotFound = errors.New("vehicle not found")

// Store is the storage contract Handler depends on. Repository is the
// Postgres-backed implementation; tests substitute an in-memory fake.
type Store interface {
	Create(ctx context.Context, input CreateInput) (*ServiceRecord, error)
	// FindByID returns nil, nil when no record has that id.
	FindByID(ctx context.Context, id string) (*ServiceRecord, error)
	// ListByPlate returns nil, nil, nil when the plate has no vehicle.
	// Records are newest first.
	ListByPlate(ctx context.Context, plate string) (*VehicleSummary, []ServiceRecord, error)
	// ListByWorkshop returns the workshop's own records, newest first.
	ListByWorkshop(ctx context.Context, workshopID string, limit int) ([]ServiceRecord, error)
	CountByWorkshopSince(ctx context.Context, workshopID string, since time.Time) (int, error)
}

var _ Store = (*Repository)(nil)
