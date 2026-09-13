//go:build integration

package servicerecord

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"mototeca-backend/internal/db"
)

// Fixtures reserved for this test; rows are removed before and after each run
// so the suite stays repeatable after a crash.
const (
	testPlateIntegration  = "ZZZ8Z88"
	testChassiIntegration = "ZZZ0000000000ZZZ8"
	testCNPJIntegration   = "99888777000199"
)

func newTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Fatal("DATABASE_URL must be set (see `make test-integration-docker`)")
	}
	pool, err := db.NewPool(context.Background(), dsn)
	if err != nil {
		t.Fatalf("connecting to database: %v", err)
	}
	t.Cleanup(pool.Close)
	return pool
}

// seed creates the workshop and vehicle a service record needs, returning the
// workshop id.
func seed(t *testing.T, pool *pgxpool.Pool) string {
	t.Helper()
	ctx := context.Background()
	cleanup(t, pool)

	var workshopID string
	if err := pool.QueryRow(ctx,
		`INSERT INTO workshops (cnpj, name) VALUES ($1, 'Oficina Integração') RETURNING id`,
		testCNPJIntegration).Scan(&workshopID); err != nil {
		t.Fatalf("seeding workshop: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO vehicles (plate, chassi, make, model, year)
		 VALUES ($1, $2, 'Honda', 'CG 160', 2022)`,
		testPlateIntegration, testChassiIntegration); err != nil {
		t.Fatalf("seeding vehicle: %v", err)
	}

	t.Cleanup(func() { cleanup(t, pool) })
	return workshopID
}

func cleanup(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	ctx := context.Background()
	// service_records cascade to operations, parts and attachments.
	if _, err := pool.Exec(ctx, `DELETE FROM vehicles WHERE plate = $1`, testPlateIntegration); err != nil {
		t.Fatalf("cleaning vehicles: %v", err)
	}
	if _, err := pool.Exec(ctx, `DELETE FROM workshops WHERE cnpj = $1`, testCNPJIntegration); err != nil {
		t.Fatalf("cleaning workshops: %v", err)
	}
}

func TestCreateWritesEveryOperationAndPart(t *testing.T) {
	pool := newTestPool(t)
	workshopID := seed(t, pool)
	repo := NewRepository(pool)
	ctx := context.Background()

	cost := 24500
	partCost := 6200
	mechanic := "José Integração"
	notes := "Observações da integração."

	created, err := repo.Create(ctx, CreateInput{
		WorkshopID:   workshopID,
		Plate:        testPlateIntegration,
		MechanicName: &mechanic,
		Operations:   []Operation{OperationOilChange, OperationChainAndSprocket},
		MileageKm:    18420,
		CostCents:    &cost,
		Notes:        &notes,
		Parts:        []Part{{Name: "Óleo 10w30", Quantity: 1, CostCents: &partCost}},
	})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	if len(created.Operations) != 2 {
		t.Errorf("operations = %d, want 2", len(created.Operations))
	}
	if len(created.Parts) != 1 {
		t.Errorf("parts = %d, want 1", len(created.Parts))
	}
	if created.WorkshopName != "Oficina Integração" {
		t.Errorf("workshopName = %q, want the joined workshop", created.WorkshopName)
	}
	if created.MechanicName == nil || *created.MechanicName != mechanic {
		t.Errorf("mechanicName = %v, want %q", created.MechanicName, mechanic)
	}
	if created.Vehicle.Plate != testPlateIntegration {
		t.Errorf("plate = %q, want %q", created.Vehicle.Plate, testPlateIntegration)
	}
}

// The same mechanic on two records must reuse one row, not accumulate one per
// service.
func TestCreateReusesTheSameMechanic(t *testing.T) {
	pool := newTestPool(t)
	workshopID := seed(t, pool)
	repo := NewRepository(pool)
	ctx := context.Background()

	mechanic := "José Integração"
	for range 2 {
		if _, err := repo.Create(ctx, CreateInput{
			WorkshopID:   workshopID,
			Plate:        testPlateIntegration,
			MechanicName: &mechanic,
			Operations:   []Operation{OperationTires},
			MileageKm:    100,
		}); err != nil {
			t.Fatalf("Create: %v", err)
		}
	}

	var count int
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM mechanics WHERE workshop_id = $1`, workshopID).Scan(&count); err != nil {
		t.Fatalf("counting mechanics: %v", err)
	}
	if count != 1 {
		t.Errorf("mechanics rows = %d, want 1 reused", count)
	}
}

func TestCreateRejectsAnUnregisteredPlate(t *testing.T) {
	pool := newTestPool(t)
	workshopID := seed(t, pool)

	_, err := NewRepository(pool).Create(context.Background(), CreateInput{
		WorkshopID: workshopID,
		Plate:      "QQQ7Q77",
		Operations: []Operation{OperationTires},
		MileageKm:  100,
	})
	if err != ErrVehicleNotFound {
		t.Errorf("err = %v, want ErrVehicleNotFound", err)
	}
}

// A rejected insert must leave nothing behind — the whole point of the
// transaction in Create.
func TestCreateRollsBackOnAnInvalidOperation(t *testing.T) {
	pool := newTestPool(t)
	workshopID := seed(t, pool)
	ctx := context.Background()

	if _, err := NewRepository(pool).Create(ctx, CreateInput{
		WorkshopID: workshopID,
		Plate:      testPlateIntegration,
		Operations: []Operation{"teleportation"}, // not in the enum
		MileageKm:  100,
	}); err == nil {
		t.Fatal("expected the invalid operation to fail")
	}

	var count int
	if err := pool.QueryRow(ctx,
		`SELECT count(*) FROM service_records WHERE workshop_id = $1`, workshopID).Scan(&count); err != nil {
		t.Fatalf("counting records: %v", err)
	}
	if count != 0 {
		t.Errorf("service_records = %d, want the transaction rolled back", count)
	}
}

func TestListByPlateIsNewestFirstAndHonoursTheLimit(t *testing.T) {
	pool := newTestPool(t)
	workshopID := seed(t, pool)
	repo := NewRepository(pool)
	ctx := context.Background()

	for _, km := range []int{100, 200, 300} {
		if _, err := repo.Create(ctx, CreateInput{
			WorkshopID: workshopID,
			Plate:      testPlateIntegration,
			Operations: []Operation{OperationTires},
			MileageKm:  km,
		}); err != nil {
			t.Fatalf("Create: %v", err)
		}
	}

	summary, records, err := repo.ListByPlate(ctx, testPlateIntegration, 2)
	if err != nil {
		t.Fatalf("ListByPlate: %v", err)
	}
	if summary == nil || summary.Plate != testPlateIntegration {
		t.Fatalf("summary = %v, want the vehicle", summary)
	}
	if len(records) != 2 {
		t.Fatalf("records = %d, want the limit of 2", len(records))
	}
	if records[0].MileageKm != 300 {
		t.Errorf("first record km = %d, want the newest (300)", records[0].MileageKm)
	}
}

func TestListByPlateReturnsNothingForAnUnknownPlate(t *testing.T) {
	pool := newTestPool(t)
	seed(t, pool)

	summary, records, err := NewRepository(pool).ListByPlate(context.Background(), "QQQ7Q77", 10)
	if err != nil {
		t.Fatalf("ListByPlate: %v", err)
	}
	if summary != nil || records != nil {
		t.Errorf("got %v / %v, want nil, nil for an unknown plate", summary, records)
	}
}

func TestReviseSupersedesTheOriginal(t *testing.T) {
	pool := newTestPool(t)
	workshopID := seed(t, pool)
	repo := NewRepository(pool)
	ctx := context.Background()

	original, err := repo.Create(ctx, CreateInput{
		WorkshopID: workshopID,
		Plate:      testPlateIntegration,
		Operations: []Operation{OperationTires},
		MileageKm:  18000,
	})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	phase := PhaseBefore
	if _, err := repo.AddAttachment(ctx, workshopID, original.ID,
		Attachment{URL: "http://storage/bucket/before.jpg", Kind: "photo", Phase: &phase}); err != nil {
		t.Fatalf("AddAttachment: %v", err)
	}

	revised, err := repo.Revise(ctx, workshopID, original.ID, CreateInput{
		WorkshopID: workshopID,
		Plate:      testPlateIntegration,
		Operations: []Operation{OperationTires, OperationSuspension},
		MileageKm:  18500,
	})
	if err != nil {
		t.Fatalf("Revise: %v", err)
	}
	if revised.RevisesRecordID == nil || *revised.RevisesRecordID != original.ID {
		t.Errorf("revisesRecordId = %v, want %q", revised.RevisesRecordID, original.ID)
	}
	if len(revised.Attachments) != 1 || revised.Attachments[0].Phase == nil || *revised.Attachments[0].Phase != PhaseBefore {
		t.Errorf("attachments = %+v, want the original's photo carried over", revised.Attachments)
	}

	// History shows the correction, not the record it replaced.
	_, records, err := repo.ListByPlate(ctx, testPlateIntegration, 10)
	if err != nil {
		t.Fatalf("ListByPlate: %v", err)
	}
	if len(records) != 1 || records[0].ID != revised.ID {
		t.Fatalf("history = %d record(s) %v, want only the correction", len(records), records)
	}

	// The original is still there, which is what makes it auditable, and it
	// points at what replaced it.
	found, err := repo.FindByID(ctx, original.ID)
	if err != nil || found == nil {
		t.Fatalf("original no longer retrievable: %v, %v", found, err)
	}
	if found.SupersededByID == nil || *found.SupersededByID != revised.ID {
		t.Errorf("supersededBy = %v, want %q", found.SupersededByID, revised.ID)
	}

	count, err := repo.CountByWorkshopSince(ctx, workshopID, original.CreatedAt.Add(-time.Hour))
	if err != nil {
		t.Fatalf("CountByWorkshopSince: %v", err)
	}
	if count != 1 {
		t.Errorf("month count = %d, want a correction not to double-count", count)
	}
}

func TestReviseRefusesAnotherWorkshopsRecord(t *testing.T) {
	pool := newTestPool(t)
	workshopID := seed(t, pool)
	repo := NewRepository(pool)
	ctx := context.Background()

	original, err := repo.Create(ctx, CreateInput{
		WorkshopID: workshopID,
		Plate:      testPlateIntegration,
		Operations: []Operation{OperationTires},
		MileageKm:  18000,
	})
	if err != nil {
		t.Fatalf("Create: %v", err)
	}

	var otherWorkshop string
	if err := pool.QueryRow(ctx,
		`INSERT INTO workshops (cnpj, name) VALUES ('99888777000166', 'Outra') RETURNING id`,
	).Scan(&otherWorkshop); err != nil {
		t.Fatalf("seeding second workshop: %v", err)
	}
	t.Cleanup(func() {
		_, _ = pool.Exec(ctx, `DELETE FROM workshops WHERE id = $1`, otherWorkshop)
	})

	if _, err := repo.Revise(ctx, otherWorkshop, original.ID, CreateInput{
		WorkshopID: otherWorkshop,
		Plate:      testPlateIntegration,
		Operations: []Operation{OperationTires},
		MileageKm:  18500,
	}); err != ErrRecordNotFound {
		t.Errorf("err = %v, want ErrRecordNotFound", err)
	}
}

func TestReviseRefusesAnAlreadyCorrectedRecord(t *testing.T) {
	pool := newTestPool(t)
	workshopID := seed(t, pool)
	repo := NewRepository(pool)
	ctx := context.Background()

	input := CreateInput{
		WorkshopID: workshopID,
		Plate:      testPlateIntegration,
		Operations: []Operation{OperationTires},
		MileageKm:  18000,
	}
	original, err := repo.Create(ctx, input)
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if _, err := repo.Revise(ctx, workshopID, original.ID, input); err != nil {
		t.Fatalf("first Revise: %v", err)
	}

	if _, err := repo.Revise(ctx, workshopID, original.ID, input); err != ErrAlreadySuperseded {
		t.Errorf("err = %v, want ErrAlreadySuperseded", err)
	}
}

func TestCreateRefusesAMileageBelowTheHighestRecorded(t *testing.T) {
	pool := newTestPool(t)
	workshopID := seed(t, pool)
	repo := NewRepository(pool)
	ctx := context.Background()

	input := CreateInput{
		WorkshopID: workshopID,
		Plate:      testPlateIntegration,
		Operations: []Operation{OperationTires},
		MileageKm:  20000,
	}
	if _, err := repo.Create(ctx, input); err != nil {
		t.Fatalf("Create: %v", err)
	}

	input.MileageKm = 15000
	_, err := repo.Create(ctx, input)
	if lower, ok := errors.AsType[*LowerMileageError](err); !ok || lower.HighestKm != 20000 {
		t.Fatalf("err = %v, want LowerMileageError at 20000 km", err)
	}

	input.ConfirmLowerMileage = true
	if _, err := repo.Create(ctx, input); err != nil {
		t.Fatalf("confirmed Create: %v", err)
	}
}
