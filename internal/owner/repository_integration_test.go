//go:build integration

package owner

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"mototeca-backend/internal/db"
	"mototeca-backend/internal/servicerecord"
)

const (
	testPlateIntegration  = "ZZZ7Z77"
	testChassiIntegration = "ZZZ0000000000ZZZ7"
	testCNPJIntegration   = "99888777000188"
	testPhoneIntegration  = "31999990000"
)

type fixture struct {
	pool       *pgxpool.Pool
	ownerID    string
	workshopID string
	records    *servicerecord.Repository
}

func setup(t *testing.T) fixture {
	t.Helper()
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Fatal("DATABASE_URL must be set (see `make test-integration-docker`)")
	}
	ctx := context.Background()
	pool, err := db.NewPool(ctx, dsn)
	if err != nil {
		t.Fatalf("connecting to database: %v", err)
	}
	t.Cleanup(pool.Close)

	clean(t, pool)
	t.Cleanup(func() { clean(t, pool) })

	f := fixture{pool: pool, records: servicerecord.NewRepository(pool)}

	o, err := NewRepository(pool).Create(ctx, CreateInput{
		Name: "Proprietário Integração", Phone: testPhoneIntegration,
	}, "digest")
	if err != nil {
		t.Fatalf("seeding owner: %v", err)
	}
	f.ownerID = o.ID

	if err := pool.QueryRow(ctx,
		`INSERT INTO workshops (cnpj, name) VALUES ($1, 'Oficina Integração') RETURNING id`,
		testCNPJIntegration).Scan(&f.workshopID); err != nil {
		t.Fatalf("seeding workshop: %v", err)
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO vehicles (plate, chassi, make, model, year)
		 VALUES ($1, $2, 'Honda', 'CG 160', 2022)`,
		testPlateIntegration, testChassiIntegration); err != nil {
		t.Fatalf("seeding vehicle: %v", err)
	}
	return f
}

func clean(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	ctx := context.Background()
	for _, stmt := range []struct{ sql, arg string }{
		{`DELETE FROM vehicles WHERE plate = $1`, testPlateIntegration},
		{`DELETE FROM workshops WHERE cnpj = $1`, testCNPJIntegration},
		{`DELETE FROM owners WHERE phone = $1`, testPhoneIntegration},
	} {
		if _, err := pool.Exec(ctx, stmt.sql, stmt.arg); err != nil {
			t.Fatalf("cleaning: %v", err)
		}
	}
}

func (f fixture) addService(t *testing.T, km int, ops ...servicerecord.Operation) *servicerecord.ServiceRecord {
	t.Helper()
	record, err := f.records.Create(context.Background(), servicerecord.CreateInput{
		WorkshopID: f.workshopID,
		Plate:      testPlateIntegration,
		Operations: ops,
		MileageKm:  km,
	})
	if err != nil {
		t.Fatalf("seeding service: %v", err)
	}
	return record
}

func TestClaimLinksTheVehicle(t *testing.T) {
	f := setup(t)
	repo := NewRepository(f.pool)

	owned, err := repo.Claim(context.Background(), f.ownerID, testPlateIntegration)
	if err != nil {
		t.Fatalf("Claim: %v", err)
	}
	if owned.Vehicle.Plate != testPlateIntegration {
		t.Errorf("plate = %q, want %q", owned.Vehicle.Plate, testPlateIntegration)
	}

	vehicles, err := repo.ListVehicles(context.Background(), f.ownerID)
	if err != nil {
		t.Fatalf("ListVehicles: %v", err)
	}
	if len(vehicles) != 1 {
		t.Fatalf("vehicles = %d, want 1", len(vehicles))
	}
}

// Claiming twice is how a user re-taps the button; it must not fail.
func TestClaimIsIdempotent(t *testing.T) {
	f := setup(t)
	repo := NewRepository(f.pool)
	ctx := context.Background()

	if _, err := repo.Claim(ctx, f.ownerID, testPlateIntegration); err != nil {
		t.Fatalf("first Claim: %v", err)
	}
	if _, err := repo.Claim(ctx, f.ownerID, testPlateIntegration); err != nil {
		t.Errorf("second Claim: %v, want it to succeed", err)
	}
}

func TestClaimRefusesSomeoneElsesVehicle(t *testing.T) {
	f := setup(t)
	repo := NewRepository(f.pool)
	ctx := context.Background()

	if _, err := repo.Claim(ctx, f.ownerID, testPlateIntegration); err != nil {
		t.Fatalf("Claim: %v", err)
	}

	other, err := repo.Create(ctx, CreateInput{Name: "Outro", Phone: "31999990001"}, "digest")
	if err != nil {
		t.Fatalf("seeding second owner: %v", err)
	}
	t.Cleanup(func() {
		_, _ = f.pool.Exec(ctx, `DELETE FROM owners WHERE id = $1`, other.ID)
	})

	if _, err := repo.Claim(ctx, other.ID, testPlateIntegration); err != ErrVehicleClaimed {
		t.Errorf("err = %v, want ErrVehicleClaimed", err)
	}
}

func TestClaimRejectsAnUnknownPlate(t *testing.T) {
	f := setup(t)

	_, err := NewRepository(f.pool).Claim(context.Background(), f.ownerID, "QQQ6Q66")
	if err != ErrVehicleNotFound {
		t.Errorf("err = %v, want ErrVehicleNotFound", err)
	}
}

// The derived columns are the whole owner screen; this is the one query that
// unit tests with a fake store cannot cover.
func TestListVehiclesDerivesTheOdometerAndOilChange(t *testing.T) {
	f := setup(t)
	repo := NewRepository(f.pool)
	ctx := context.Background()

	if _, err := repo.Claim(ctx, f.ownerID, testPlateIntegration); err != nil {
		t.Fatalf("Claim: %v", err)
	}
	f.addService(t, 15000, servicerecord.OperationOilChange)
	f.addService(t, 16000, servicerecord.OperationBrakes)
	f.addService(t, 17600, servicerecord.OperationTires)

	vehicles, err := repo.ListVehicles(ctx, f.ownerID)
	if err != nil {
		t.Fatalf("ListVehicles: %v", err)
	}
	got := vehicles[0]

	if got.CurrentMileageKm != 17600 {
		t.Errorf("currentMileageKm = %d, want the highest recorded (17600)", got.CurrentMileageKm)
	}
	if got.ServiceCount != 3 {
		t.Errorf("serviceCount = %d, want 3", got.ServiceCount)
	}
	if got.LastOilChangeKm == nil || *got.LastOilChangeKm != 15000 {
		t.Errorf("lastOilChangeKm = %v, want 15000 — the brakes and tyres jobs must not count", got.LastOilChangeKm)
	}
	if got.LastServiceID == nil {
		t.Fatal("expected the newest record id")
	}

	// 15000 + 3000 interval - 17600 = 400 km left.
	if reminder := got.Reminder(); reminder.Text != "Troca de óleo em 400 km" || !reminder.IsDue {
		t.Errorf("reminder = %+v, want the 400 km warning", reminder)
	}
}

func TestListVehiclesHandlesABikeWithNoHistory(t *testing.T) {
	f := setup(t)
	repo := NewRepository(f.pool)
	ctx := context.Background()

	if _, err := repo.Claim(ctx, f.ownerID, testPlateIntegration); err != nil {
		t.Fatalf("Claim: %v", err)
	}

	vehicles, err := repo.ListVehicles(ctx, f.ownerID)
	if err != nil {
		t.Fatalf("ListVehicles: %v", err)
	}
	got := vehicles[0]

	if got.CurrentMileageKm != 0 || got.ServiceCount != 0 {
		t.Errorf("got km=%d count=%d, want zeroes", got.CurrentMileageKm, got.ServiceCount)
	}
	if got.LastServiceID != nil || got.LastOilChangeKm != nil {
		t.Error("expected no last service and no oil change")
	}
	if reminder := got.Reminder(); reminder.Text != "Sem serviços registrados" {
		t.Errorf("reminder = %q, want the no-history message", reminder.Text)
	}
}

func TestFindByPhoneReturnsNilWhenUnregistered(t *testing.T) {
	f := setup(t)

	got, err := NewRepository(f.pool).FindByPhone(context.Background(), "31900000000")
	if err != nil {
		t.Fatalf("FindByPhone: %v", err)
	}
	if got != nil {
		t.Errorf("got %v, want nil", got)
	}
}

func TestCreateRejectsADuplicatePhone(t *testing.T) {
	f := setup(t)

	_, err := NewRepository(f.pool).Create(context.Background(),
		CreateInput{Name: "Outro", Phone: testPhoneIntegration}, "digest")
	if err != ErrDuplicatePhone {
		t.Errorf("err = %v, want ErrDuplicatePhone", err)
	}
}

// The point of keying history to the plate: a sale moves the bike between
// owners without touching its service record.
func TestReleaseAllowsANewOwnerToClaim(t *testing.T) {
	f := setup(t)
	repo := NewRepository(f.pool)
	ctx := context.Background()

	if _, err := repo.Claim(ctx, f.ownerID, testPlateIntegration); err != nil {
		t.Fatalf("Claim: %v", err)
	}
	f.addService(t, 15000, servicerecord.OperationOilChange)

	buyer, err := repo.Create(ctx, CreateInput{Name: "Comprador", Phone: "31999990002"}, "digest")
	if err != nil {
		t.Fatalf("seeding buyer: %v", err)
	}
	t.Cleanup(func() { _, _ = f.pool.Exec(ctx, `DELETE FROM owners WHERE id = $1`, buyer.ID) })

	// The buyer cannot take it while the seller still holds it.
	if _, err := repo.Claim(ctx, buyer.ID, testPlateIntegration); err != ErrVehicleClaimed {
		t.Fatalf("err = %v, want ErrVehicleClaimed before release", err)
	}

	if err := repo.Release(ctx, f.ownerID, testPlateIntegration); err != nil {
		t.Fatalf("Release: %v", err)
	}

	owned, err := repo.Claim(ctx, buyer.ID, testPlateIntegration)
	if err != nil {
		t.Fatalf("Claim after release: %v", err)
	}
	if owned.ServiceCount != 1 {
		t.Errorf("serviceCount = %d, want the history to survive the sale", owned.ServiceCount)
	}

	sellerVehicles, err := repo.ListVehicles(ctx, f.ownerID)
	if err != nil {
		t.Fatalf("ListVehicles: %v", err)
	}
	if len(sellerVehicles) != 0 {
		t.Errorf("seller still has %d vehicle(s)", len(sellerVehicles))
	}
}

func TestReleaseRefusesABikeYouDoNotHold(t *testing.T) {
	f := setup(t)
	repo := NewRepository(f.pool)
	ctx := context.Background()

	// Nobody owns it yet.
	if err := repo.Release(ctx, f.ownerID, testPlateIntegration); err != ErrVehicleNotFound {
		t.Errorf("err = %v, want ErrVehicleNotFound", err)
	}

	if _, err := repo.Claim(ctx, f.ownerID, testPlateIntegration); err != nil {
		t.Fatalf("Claim: %v", err)
	}
	stranger, err := repo.Create(ctx, CreateInput{Name: "Estranho", Phone: "31999990003"}, "digest")
	if err != nil {
		t.Fatalf("seeding stranger: %v", err)
	}
	t.Cleanup(func() { _, _ = f.pool.Exec(ctx, `DELETE FROM owners WHERE id = $1`, stranger.ID) })

	if err := repo.Release(ctx, stranger.ID, testPlateIntegration); err != ErrVehicleNotFound {
		t.Errorf("err = %v, want a stranger's release to be refused", err)
	}
}

// A mileage typo that was corrected must not keep inflating the odometer.
func TestListVehiclesIgnoresSupersededRecords(t *testing.T) {
	f := setup(t)
	repo := NewRepository(f.pool)
	ctx := context.Background()

	if _, err := repo.Claim(ctx, f.ownerID, testPlateIntegration); err != nil {
		t.Fatalf("Claim: %v", err)
	}
	f.addService(t, 15000, servicerecord.OperationBrakes)
	typo := f.addService(t, 160000, servicerecord.OperationOilChange)

	correction, err := f.records.Revise(ctx, f.workshopID, typo.ID, servicerecord.CreateInput{
		WorkshopID: f.workshopID,
		Plate:      testPlateIntegration,
		Operations: []servicerecord.Operation{servicerecord.OperationOilChange},
		MileageKm:  16000,
	})
	if err != nil {
		t.Fatalf("Revise: %v", err)
	}

	vehicles, err := repo.ListVehicles(ctx, f.ownerID)
	if err != nil {
		t.Fatalf("ListVehicles: %v", err)
	}
	got := vehicles[0]

	if got.CurrentMileageKm != 16000 {
		t.Errorf("currentMileageKm = %d, want the corrected 16000", got.CurrentMileageKm)
	}
	if got.ServiceCount != 2 {
		t.Errorf("serviceCount = %d, want 2 — a correction is not an extra service", got.ServiceCount)
	}
	if got.LastOilChangeKm == nil || *got.LastOilChangeKm != 16000 {
		t.Errorf("lastOilChangeKm = %v, want 16000", got.LastOilChangeKm)
	}
	if got.LastServiceID == nil || *got.LastServiceID != correction.ID {
		t.Errorf("lastServiceId = %v, want the correction %q", got.LastServiceID, correction.ID)
	}
}
