package vehicle

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const selectColumns = `id, plate, chassi, make, model, year, current_owner_id, created_at`

func scanVehicle(row pgx.Row) (*Vehicle, error) {
	var v Vehicle
	if err := row.Scan(&v.ID, &v.Plate, &v.Chassi, &v.Make, &v.Model, &v.Year, &v.CurrentOwnerID, &v.CreatedAt); err != nil {
		return nil, err
	}
	return &v, nil
}

// FindByPlate returns nil (no error) when the plate has no history yet.
func (r *Repository) FindByPlate(ctx context.Context, plate string) (*Vehicle, error) {
	row := r.pool.QueryRow(ctx, `SELECT `+selectColumns+` FROM vehicles WHERE plate = $1`, plate)

	v, err := scanVehicle(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return v, nil
}

func (r *Repository) Create(ctx context.Context, input CreateInput) (*Vehicle, error) {
	plate := NormalizePlate(input.Plate)
	row := r.pool.QueryRow(ctx,
		`INSERT INTO vehicles (plate, chassi, make, model, year)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING `+selectColumns,
		plate, input.Chassi, input.Make, input.Model, input.Year)

	return scanVehicle(row)
}
