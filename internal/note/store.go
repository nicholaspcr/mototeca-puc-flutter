package note

import (
	"context"
	"errors"
	"time"
)

var (
	// ErrNotOwned covers a missing plate and someone else's bike alike, so the
	// answer never reveals who owns what.
	ErrNotOwned = errors.New("vehicle not owned by caller")
	// ErrNotFound is returned when the note does not exist, is someone
	// else's, or its bike was sold since.
	ErrNotFound = errors.New("note not found")
	// ErrPhotoExists is returned when the note already has its one photo.
	ErrPhotoExists = errors.New("note already has a photo")
)

// Store is the storage contract the handlers depend on. Repository is the
// Postgres-backed implementation; tests substitute an in-memory fake.
type Store interface {
	// Add publishes a note on a bike the owner holds. Sending the same
	// client id again returns the note already stored.
	Add(ctx context.Context, input AddInput, doneOn time.Time) (*Note, error)
	// Delete removes the owner's note while they still own the bike, and
	// returns its photo URL so the file can go too.
	Delete(ctx context.Context, ownerID, id string) (photoURL *string, err error)
	// FindOwned returns nil, nil unless the note is the owner's and the bike
	// still is too.
	FindOwned(ctx context.Context, ownerID, id string) (*Note, error)
	// SetPhoto attaches the note's one photo.
	SetPhoto(ctx context.Context, ownerID, id, url string) error
	// ListByPlate returns the plate's notes, newest day first.
	ListByPlate(ctx context.Context, plate string, limit int) ([]Note, error)
}

var _ Store = (*Repository)(nil)
