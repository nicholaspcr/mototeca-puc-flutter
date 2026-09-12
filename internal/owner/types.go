package owner

import (
	"time"

	"mototeca-backend/internal/servicerecord"
)

type Owner struct {
	ID      string  `json:"id"`
	Name    string  `json:"name"`
	Phone   string  `json:"phone"`
	CPFHash *string `json:"-"`
	// PasswordHash never leaves the server: json:"-" so an accidental marshal
	// of this struct cannot leak the digest.
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"createdAt"`
}

type CreateInput struct {
	Name     string `json:"name"`
	Phone    string `json:"phone"`
	Password string `json:"-"`
}

// OwnedVehicle is one row of "Minhas Motos": the bike plus the figures derived
// from its service history, which is where the owner's screen gets its status
// from. No separate reminders table — the history already says everything
// needed to work out what is due.
type OwnedVehicle struct {
	Vehicle          servicerecord.VehicleSummary
	CurrentMileageKm int
	ServiceCount     int
	// Newest record, so the screen can show what was last done. Nil when the
	// bike has no history yet.
	LastServiceID *string
	// Mileage at the most recent oil change, which is what the reminder
	// counts from. Nil when none was ever recorded.
	LastOilChangeKm *int
}
