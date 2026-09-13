//go:build integration

package vehicle

import (
	"context"
	"errors"
	"os"
	"testing"

	"mototeca-backend/internal/db"
)

// integrationTestPlate and integrationTestChassi are reserved for this test
// (plate and chassi both have unique constraints); rows are deleted before
// and after each run so the suite stays repeatable even after a crash.
const (
	integrationTestPlate  = "ZZZ9Z99"
	integrationTestChassi = "ZZZ0000000000ZZZZ"
)

func TestRepositoryIntegration(t *testing.T) {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		t.Fatal("DATABASE_URL must be set to run integration tests (see `make db-up`)")
	}

	ctx := context.Background()
	pool, err := db.NewPool(ctx, dsn)
	if err != nil {
		t.Fatalf("connecting to database: %v", err)
	}
	// Cleanup funcs run LIFO, so registering pool.Close first guarantees the
	// row-cleanup below runs against a still-open pool.
	t.Cleanup(pool.Close)

	repo := NewRepository(pool)

	cleanup := func() {
		if _, err := pool.Exec(ctx, `DELETE FROM vehicles WHERE plate = $1 OR chassi = $2`, integrationTestPlate, integrationTestChassi); err != nil {
			t.Logf("cleanup: deleting test vehicle: %v", err)
		}
	}
	cleanup()
	t.Cleanup(cleanup)

	t.Run("not found returns nil, nil", func(t *testing.T) {
		v, err := repo.FindByPlate(ctx, integrationTestPlate)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if v != nil {
			t.Fatalf("expected nil vehicle, got %+v", v)
		}
	})

	t.Run("create then find round-trip", func(t *testing.T) {
		input := CreateInput{
			Plate:  integrationTestPlate,
			Chassi: integrationTestChassi,
			Make:   "Honda",
			Model:  "CG 160 Start",
			Year:   2022,
		}
		created, err := repo.Create(ctx, input)
		if err != nil {
			t.Fatalf("Create: %v", err)
		}
		if created.ID == "" {
			t.Error("expected generated ID, got empty string")
		}

		found, err := repo.FindByPlate(ctx, integrationTestPlate)
		if err != nil {
			t.Fatalf("FindByPlate: %v", err)
		}
		if found == nil {
			t.Fatal("expected to find the vehicle just created")
		}
		if found.Plate != integrationTestPlate {
			t.Errorf("Plate = %q, want %q", found.Plate, integrationTestPlate)
		}
		if found.Make != input.Make || found.Model != input.Model {
			t.Errorf("Make/Model = %q/%q, want %q/%q", found.Make, found.Model, input.Make, input.Model)
		}
	})

	t.Run("duplicates name the key that clashed", func(t *testing.T) {
		samePlate := CreateInput{Plate: integrationTestPlate, Chassi: "ZZZ1111111111ZZZZ", Make: "Honda", Model: "CG", Year: 2022}
		if _, err := repo.Create(ctx, samePlate); !errors.Is(err, ErrDuplicatePlate) {
			t.Errorf("same plate: err = %v, want ErrDuplicatePlate", err)
		}

		sameChassi := CreateInput{Plate: "ZZZ9Z98", Chassi: integrationTestChassi, Make: "Honda", Model: "CG", Year: 2022}
		if _, err := repo.Create(ctx, sameChassi); !errors.Is(err, ErrDuplicateChassi) {
			t.Errorf("same chassi: err = %v, want ErrDuplicateChassi", err)
		}
	})
}
