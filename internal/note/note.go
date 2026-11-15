// Package note holds the maintenance notes owners publish to a plate's
// history. They sit beside the workshop records but never mix with them: no
// shop vouches for a note.
package note

import (
	"context"
	"errors"
	"fmt"
	"strings"
	"time"
	"unicode/utf8"

	"github.com/google/uuid"
	"google.golang.org/protobuf/types/known/timestamppb"

	servicev1 "mototeca-backend/internal/gen/mototeca/service/v1"
)

// DateLayout is how a note's day travels: a calendar day, not an instant.
const DateLayout = time.DateOnly

const (
	maxDescriptionLength = 500
	maxMileageKm         = 2_000_000
	maxCostCents         = 100_000_000
	// MaxPerPlate caps what the public lookup returns in one response.
	MaxPerPlate = 100
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

type Note struct {
	ID          string
	DoneOn      time.Time
	Description string
	MileageKm   *int
	CostCents   *int
	PhotoURL    *string
	CreatedAt   time.Time
}

type AddInput struct {
	OwnerID     string
	Plate       string
	ClientID    string
	DoneOn      string
	Description string
	MileageKm   *int
	CostCents   *int
}

// Validate checks the input and returns the parsed day. now bounds the day,
// with a day of slack for owners east of the server's clock.
func (input AddInput) Validate(now time.Time) (time.Time, error) {
	if uuid.Validate(input.ClientID) != nil {
		return time.Time{}, fmt.Errorf("identificador da anotação inválido")
	}
	description := strings.TrimSpace(input.Description)
	if description == "" || utf8.RuneCountInString(description) > maxDescriptionLength {
		return time.Time{}, fmt.Errorf("descreva o que foi feito (até %d caracteres)", maxDescriptionLength)
	}
	doneOn, err := time.Parse(DateLayout, input.DoneOn)
	if err != nil {
		return time.Time{}, fmt.Errorf("data inválida")
	}
	if doneOn.After(now.AddDate(0, 0, 1)) {
		return time.Time{}, fmt.Errorf("a data não pode estar no futuro")
	}
	if input.MileageKm != nil && (*input.MileageKm < 0 || *input.MileageKm > maxMileageKm) {
		return time.Time{}, fmt.Errorf("quilometragem deve estar entre 0 e %d km", maxMileageKm)
	}
	if input.CostCents != nil && (*input.CostCents < 0 || *input.CostCents > maxCostCents) {
		return time.Time{}, fmt.Errorf("valor fora do limite")
	}
	return doneOn, nil
}

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

func ToProto(n Note) *servicev1.MaintenanceNote {
	out := &servicev1.MaintenanceNote{
		Id:          n.ID,
		DoneOn:      n.DoneOn.Format(DateLayout),
		Description: n.Description,
		PhotoUrl:    n.PhotoURL,
		CreatedAt:   timestamppb.New(n.CreatedAt),
	}
	if n.MileageKm != nil {
		km := int32(*n.MileageKm)
		out.MileageKm = &km
	}
	if n.CostCents != nil {
		cents := int32(*n.CostCents)
		out.CostCents = &cents
	}
	return out
}

func ListToProto(notes []Note) []*servicev1.MaintenanceNote {
	out := make([]*servicev1.MaintenanceNote, 0, len(notes))
	for _, n := range notes {
		out = append(out, ToProto(n))
	}
	return out
}
