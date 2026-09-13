//go:build integration

package workshop

import (
	"context"
	"os"
	"testing"

	"github.com/jackc/pgx/v5/pgxpool"

	"mototeca-backend/internal/db"
)

const testCNPJIntegration = "99888777000177"

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

	clean(t, pool)
	t.Cleanup(func() { clean(t, pool) })
	return pool
}

func clean(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	if _, err := pool.Exec(context.Background(),
		`DELETE FROM workshops WHERE cnpj = $1`, testCNPJIntegration); err != nil {
		t.Fatalf("cleaning workshops: %v", err)
	}
}

func TestCreateAndFindRoundTrip(t *testing.T) {
	repo := NewRepository(newTestPool(t))
	ctx := context.Background()
	address := "Rua Integração, 100"

	created, err := repo.Create(ctx, CreateInput{
		CNPJ: "99.888.777/0001-77", Name: "Oficina Integração", Address: &address,
	}, "a-bcrypt-digest")
	if err != nil {
		t.Fatalf("Create: %v", err)
	}
	if created.CNPJ != testCNPJIntegration {
		t.Errorf("cnpj = %q, want it stored normalized", created.CNPJ)
	}
	if created.Verified {
		t.Error("a new workshop must not start verified")
	}

	found, err := repo.FindByCNPJ(ctx, testCNPJIntegration)
	if err != nil {
		t.Fatalf("FindByCNPJ: %v", err)
	}
	if found == nil || found.PasswordHash != "a-bcrypt-digest" {
		t.Fatalf("found = %v, want the stored digest back for Login to check", found)
	}

	byID, err := repo.FindByID(ctx, created.ID)
	if err != nil || byID == nil || byID.ID != created.ID {
		t.Fatalf("FindByID = %v, %v", byID, err)
	}
}

func TestCreateRejectsADuplicateCNPJ(t *testing.T) {
	repo := NewRepository(newTestPool(t))
	ctx := context.Background()
	input := CreateInput{CNPJ: testCNPJIntegration, Name: "Oficina Integração"}

	if _, err := repo.Create(ctx, input, "digest"); err != nil {
		t.Fatalf("first Create: %v", err)
	}
	if _, err := repo.Create(ctx, input, "digest"); err != ErrDuplicateCNPJ {
		t.Errorf("err = %v, want ErrDuplicateCNPJ", err)
	}
}

func TestFindReturnsNilWhenAbsent(t *testing.T) {
	repo := NewRepository(newTestPool(t))
	ctx := context.Background()

	byCNPJ, err := repo.FindByCNPJ(ctx, "00000000000000")
	if err != nil || byCNPJ != nil {
		t.Errorf("FindByCNPJ = %v, %v; want nil, nil", byCNPJ, err)
	}

	byID, err := repo.FindByID(ctx, "00000000-0000-0000-0000-000000000000")
	if err != nil || byID != nil {
		t.Errorf("FindByID = %v, %v; want nil, nil", byID, err)
	}
}
