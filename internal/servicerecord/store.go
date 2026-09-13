package servicerecord

import (
	"context"
	"errors"
	"fmt"
	"time"
)

var (
	// ErrRecordNotFound is returned by Revise when the record does not exist
	// or belongs to another workshop — indistinguishable to the caller.
	ErrRecordNotFound = errors.New("service record not found")
	// ErrAlreadySuperseded is returned by Revise for an already-corrected
	// record; the correction is what should be revised instead.
	ErrAlreadySuperseded = errors.New("service record already superseded")
	// ErrVehicleNotFound is returned by Create when the plate has no vehicle.
	ErrVehicleNotFound = errors.New("vehicle not found")
	// ErrTooManyAttachments is returned by AddAttachment past the per-record cap.
	ErrTooManyAttachments = errors.New("too many attachments")
)

// MaxAttachmentsPerRecord bounds what one record can store: several photos
// per phase and an invoice, not an unbounded bucket anyone can fill.
const MaxAttachmentsPerRecord = 20

// LowerMileageError is returned by Create for a mileage below the bike's
// highest recorded one, unless the input confirms it.
type LowerMileageError struct {
	HighestKm int
}

func (e *LowerMileageError) Error() string {
	return fmt.Sprintf("mileage below the highest recorded (%d km)", e.HighestKm)
}

// Store is the storage contract Handler depends on. Repository is the
// Postgres-backed implementation; tests substitute an in-memory fake.
type Store interface {
	Create(ctx context.Context, input CreateInput) (*ServiceRecord, error)
	// Revise writes a correction and points the original at it. workshopID
	// must own the record being revised.
	Revise(ctx context.Context, workshopID, recordID string, input CreateInput) (*ServiceRecord, error)
	// FindByID returns nil, nil when no record has that id.
	FindByID(ctx context.Context, id string) (*ServiceRecord, error)
	// ListByPlate returns nil, nil, nil when the plate has no vehicle.
	// Records are newest first.
	ListByPlate(ctx context.Context, plate string, limit int) (*VehicleSummary, []ServiceRecord, error)
	// ListByWorkshop returns the workshop's own records, newest first.
	ListByWorkshop(ctx context.Context, workshopID string, limit int) ([]ServiceRecord, error)
	CountByWorkshopSince(ctx context.Context, workshopID string, since time.Time) (int, error)
	// AddAttachment links a stored file to a record the workshop owns.
	AddAttachment(ctx context.Context, workshopID, recordID string, a Attachment) (*Attachment, error)
}

var _ Store = (*Repository)(nil)
