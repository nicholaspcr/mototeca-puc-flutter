//go:build integration

package note

import (
	"context"
	"errors"
	"os"
	"testing"
	"time"

	"github.com/jackc/pgx/v5/pgxpool"

	"mototeca-backend/internal/db"
)

const (
	testPlate  = "NNN5N55"
	testChassi = "NNN0000000000NNN5"
	testPhone  = "31999995555"
	otherPhone = "31999995556"
	clientID   = "0f8fad5b-d9cb-469f-a165-70867728950e"
)

type fixture struct {
	repo    *Repository
	pool    *pgxpool.Pool
	ownerID string
	otherID string
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

	f := fixture{repo: NewRepository(pool), pool: pool}
	for phone, id := range map[string]*string{testPhone: &f.ownerID, otherPhone: &f.otherID} {
		if err := pool.QueryRow(ctx,
			`INSERT INTO owners (name, phone) VALUES ('Dono', $1) RETURNING id`, phone,
		).Scan(id); err != nil {
			t.Fatalf("seeding owner: %v", err)
		}
	}
	if _, err := pool.Exec(ctx,
		`INSERT INTO vehicles (plate, chassi, make, model, year, current_owner_id)
		 VALUES ($1, $2, 'Honda', 'CG 160', 2022, $3)`, testPlate, testChassi, f.ownerID); err != nil {
		t.Fatalf("seeding vehicle: %v", err)
	}
	return f
}

func clean(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	for _, stmt := range []struct{ sql, arg string }{
		{`DELETE FROM vehicles WHERE plate = $1`, testPlate},
		{`DELETE FROM owners WHERE phone = $1`, testPhone},
		{`DELETE FROM owners WHERE phone = $1`, otherPhone},
	} {
		if _, err := pool.Exec(context.Background(), stmt.sql, stmt.arg); err != nil {
			t.Fatalf("cleaning: %v", err)
		}
	}
}

func (f fixture) add(t *testing.T, ownerID, client, day string) (*Note, error) {
	t.Helper()
	doneOn, err := time.Parse(DateLayout, day)
	if err != nil {
		t.Fatal(err)
	}
	return f.repo.Add(context.Background(), AddInput{
		OwnerID: ownerID, Plate: testPlate, ClientID: client, Description: "Troca de óleo",
	}, doneOn)
}

func TestAddIsIdempotentAndOnlyForTheOwner(t *testing.T) {
	f := setup(t)

	first, err := f.add(t, f.ownerID, clientID, "2026-10-03")
	if err != nil {
		t.Fatalf("Add: %v", err)
	}
	retry, err := f.add(t, f.ownerID, clientID, "2026-10-03")
	if err != nil || retry.ID != first.ID {
		t.Fatalf("retry = %v, %v; want the note already stored (%s)", retry, err, first.ID)
	}

	if _, err := f.add(t, f.otherID, "1b4e28ba-2fa1-11d2-883f-0016d3cca427", "2026-10-03"); !errors.Is(err, ErrNotOwned) {
		t.Errorf("someone else's bike: err = %v, want ErrNotOwned", err)
	}
}

func TestListByPlateIsNewestDayFirst(t *testing.T) {
	f := setup(t)
	if _, err := f.add(t, f.ownerID, clientID, "2026-01-10"); err != nil {
		t.Fatal(err)
	}
	if _, err := f.add(t, f.ownerID, "1b4e28ba-2fa1-11d2-883f-0016d3cca427", "2026-06-20"); err != nil {
		t.Fatal(err)
	}

	notes, err := f.repo.ListByPlate(context.Background(), testPlate, 10)
	if err != nil {
		t.Fatalf("ListByPlate: %v", err)
	}
	if len(notes) != 2 || notes[0].DoneOn.Format(DateLayout) != "2026-06-20" {
		t.Errorf("notes = %+v, want 2026-06-20 first", notes)
	}
}

// After a sale the notes stay in the history, out of the seller's reach.
func TestASoldBikesNotesCannotBeChanged(t *testing.T) {
	f := setup(t)
	added, err := f.add(t, f.ownerID, clientID, "2026-10-03")
	if err != nil {
		t.Fatal(err)
	}
	ctx := context.Background()
	if err := f.repo.SetPhoto(ctx, f.ownerID, added.ID, "http://storage/a.jpg"); err != nil {
		t.Fatalf("SetPhoto: %v", err)
	}
	if err := f.repo.SetPhoto(ctx, f.ownerID, added.ID, "http://storage/b.jpg"); !errors.Is(err, ErrPhotoExists) {
		t.Errorf("second photo: err = %v, want ErrPhotoExists", err)
	}

	if _, err := f.pool.Exec(ctx, `UPDATE vehicles SET current_owner_id = NULL WHERE plate = $1`, testPlate); err != nil {
		t.Fatal(err)
	}
	if _, err := f.repo.Delete(ctx, f.ownerID, added.ID); !errors.Is(err, ErrNotFound) {
		t.Errorf("delete after sale: err = %v, want ErrNotFound", err)
	}
	if notes, _ := f.repo.ListByPlate(ctx, testPlate, 10); len(notes) != 1 {
		t.Errorf("notes after sale = %d, want the note kept", len(notes))
	}
}
