// Package note holds the maintenance notes owners publish to a plate's
// history. They sit beside the workshop records but never mix with them: no
// shop vouches for a note.
package note

import (
	"time"

	"google.golang.org/protobuf/types/known/timestamppb"

	servicev1 "mototeca-backend/internal/gen/mototeca/service/v1"
)

// DateLayout is how a note's day travels: a calendar day, not an instant.
const DateLayout = time.DateOnly

// MaxPerPlate caps what the public lookup returns in one response.
const MaxPerPlate = 100

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
