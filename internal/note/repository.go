package note

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const columns = `n.id, n.done_on, n.description, n.mileage_km, n.cost_cents, n.photo_url, n.created_at`

// owned limits a query to notes the owner wrote on a bike they still hold.
const owned = `n.id = $1 AND n.owner_id = $2
	AND n.vehicle_id IN (SELECT id FROM vehicles WHERE current_owner_id = $2)`

func scan(row pgx.Row) (*Note, error) {
	var n Note
	err := row.Scan(&n.ID, &n.DoneOn, &n.Description, &n.MileageKm, &n.CostCents, &n.PhotoURL, &n.CreatedAt)
	if err != nil {
		return nil, err
	}
	return &n, nil
}

// validID keeps a malformed id away from the uuid column, where Postgres would
// fail the query instead of simply finding nothing.
func validID(id string) bool {
	return len(id) == 36 && uuid.Validate(id) == nil
}

func (r *Repository) Add(ctx context.Context, input AddInput, doneOn time.Time) (*Note, error) {
	n, err := scan(r.pool.QueryRow(ctx,
		`INSERT INTO maintenance_notes AS n
		   (vehicle_id, owner_id, client_id, done_on, description, mileage_km, cost_cents)
		 SELECT v.id, $2, $3, $4, $5, $6, $7
		   FROM vehicles v WHERE v.plate = $1 AND v.current_owner_id = $2
		 ON CONFLICT (owner_id, client_id) DO NOTHING
		 RETURNING `+columns,
		input.Plate, input.OwnerID, input.ClientID, doneOn, input.Description,
		input.MileageKm, input.CostCents))
	if !errors.Is(err, pgx.ErrNoRows) {
		return n, err
	}

	// Either a retry of a note already stored, or a bike the caller does not own.
	n, err = scan(r.pool.QueryRow(ctx,
		`SELECT `+columns+` FROM maintenance_notes n WHERE n.owner_id = $1 AND n.client_id = $2`,
		input.OwnerID, input.ClientID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotOwned
	}
	return n, err
}

func (r *Repository) Delete(ctx context.Context, ownerID, id string) (*string, error) {
	if !validID(id) {
		return nil, ErrNotFound
	}
	var photoURL *string
	err := r.pool.QueryRow(ctx,
		`DELETE FROM maintenance_notes n WHERE `+owned+` RETURNING n.photo_url`, id, ownerID,
	).Scan(&photoURL)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrNotFound
	}
	return photoURL, err
}

func (r *Repository) FindOwned(ctx context.Context, ownerID, id string) (*Note, error) {
	if !validID(id) {
		return nil, nil
	}
	n, err := scan(r.pool.QueryRow(ctx,
		`SELECT `+columns+` FROM maintenance_notes n WHERE `+owned, id, ownerID))
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	return n, err
}

func (r *Repository) SetPhoto(ctx context.Context, ownerID, id, url string) error {
	if !validID(id) {
		return ErrNotFound
	}
	var hadPhoto bool
	err := r.pool.QueryRow(ctx,
		`UPDATE maintenance_notes n SET photo_url = COALESCE(n.photo_url, $3)
		 WHERE `+owned+`
		 RETURNING n.photo_url <> $3`, id, ownerID, url,
	).Scan(&hadPhoto)
	if errors.Is(err, pgx.ErrNoRows) {
		return ErrNotFound
	}
	if err != nil {
		return err
	}
	if hadPhoto {
		return ErrPhotoExists
	}
	return nil
}

func (r *Repository) ListByPlate(ctx context.Context, plate string, limit int) ([]Note, error) {
	rows, err := r.pool.Query(ctx,
		`SELECT `+columns+` FROM maintenance_notes n
		 JOIN vehicles v ON v.id = n.vehicle_id
		 WHERE v.plate = $1
		 ORDER BY n.done_on DESC, n.created_at DESC
		 LIMIT $2`, plate, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	var notes []Note
	for rows.Next() {
		n, err := scan(rows)
		if err != nil {
			return nil, err
		}
		notes = append(notes, *n)
	}
	return notes, rows.Err()
}
