package servicerecord

import "time"

// Operation is one entry of the fixed taxonomy. The values are exactly the
// labels of the `service_type` Postgres enum (db/migrations/0001_init.sql) and
// the chips on the Novo Registro screen.
type Operation string

const (
	OperationOilChange        Operation = "oil_change"
	OperationScheduledReview  Operation = "scheduled_review"
	OperationBrakes           Operation = "brakes"
	OperationChainAndSprocket Operation = "chain_and_sprocket"
	OperationTires            Operation = "tires"
	OperationElectrical       Operation = "electrical"
	OperationSparkPlugs       Operation = "spark_plugs"
	OperationSuspension       Operation = "suspension"
	OperationClutch           Operation = "clutch"
	OperationFuelInjection    Operation = "fuel_injection"
	OperationBodywork         Operation = "bodywork"
	OperationOther            Operation = "other"
)

// validOperations gates what reaches the database. A value outside this set
// would be rejected by the enum anyway, but failing in validation gives the
// client an INVALID_ARGUMENT instead of an opaque INTERNAL.
var validOperations = map[Operation]bool{
	OperationOilChange: true, OperationScheduledReview: true, OperationBrakes: true,
	OperationChainAndSprocket: true, OperationTires: true, OperationElectrical: true,
	OperationSparkPlugs: true, OperationSuspension: true, OperationClutch: true,
	OperationFuelInjection: true, OperationBodywork: true, OperationOther: true,
}

func (o Operation) Valid() bool { return validOperations[o] }

// Photo phases. Stored in attachments.phase; nil on an invoice.
const (
	PhaseBefore = "before"
	PhaseAfter  = "after"
)

type Part struct {
	Name      string `json:"name"`
	Quantity  int    `json:"quantity"`
	CostCents *int   `json:"costCents"`
}

type Attachment struct {
	ID    string  `json:"id"`
	URL   string  `json:"url"`
	Kind  string  `json:"kind"`
	Phase *string `json:"phase"`
}

// VehicleSummary is the subset of vehicle fields safe to return on the public
// plate lookup — no chassi, no owner (ARCHITECTURE.md section 8).
type VehicleSummary struct {
	Plate string `json:"plate"`
	Make  string `json:"make"`
	Model string `json:"model"`
	Year  int    `json:"year"`
}

type ServiceRecord struct {
	ID string `json:"id"`
	// WorkshopID is who may attach files or revise; never sent to clients.
	WorkshopID   string         `json:"-"`
	Vehicle      VehicleSummary `json:"vehicle"`
	WorkshopName string         `json:"workshopName"`
	MechanicName *string        `json:"mechanicName"`
	Operations   []Operation    `json:"operations"`
	MileageKm    int            `json:"mileageKm"`
	CostCents    *int           `json:"costCents"`
	Notes        *string        `json:"notes"`
	Parts        []Part         `json:"parts"`
	Attachments  []Attachment   `json:"attachments"`
	CreatedAt    time.Time      `json:"createdAt"`
	// Set when this record corrects an earlier one.
	RevisesRecordID *string `json:"revisesRecordId"`
	// Set when a later correction replaced this record.
	SupersededByID *string `json:"supersededByRecordId"`
}

type CreateInput struct {
	// WorkshopID comes from the session token, never from the request body:
	// a shop can only ever write records under its own name.
	WorkshopID   string
	Plate        string
	MechanicName *string
	Operations   []Operation
	MileageKm    int
	CostCents    *int
	Notes        *string
	Parts        []Part
	// Set to correct an existing record instead of adding a new one. The
	// original is superseded, never edited.
	RevisesRecordID *string
	// ConfirmLowerMileage accepts a mileage below the highest on record.
	ConfirmLowerMileage bool
}
