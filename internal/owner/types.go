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

// OwnedVehicle is one row of "Minhas Motos". There is no reminders table: the
// service history already says everything needed to work out what is due.
type OwnedVehicle struct {
	Vehicle          servicerecord.VehicleSummary
	CurrentMileageKm int
	ServiceCount     int
	// Nil when the bike has no history yet.
	LastServiceID *string
	// What the reminder counts from. Nil when no oil change was recorded.
	LastOilChangeKm *int
}
