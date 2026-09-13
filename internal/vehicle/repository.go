package vehicle

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const selectColumns = `id, plate, chassi, make, model, year, created_at`

// uniqueViolation is Postgres' SQLSTATE for a duplicate key.
const uniqueViolation = "23505"

func scanVehicle(row pgx.Row) (*Vehicle, error) {
	var v Vehicle
	if err := row.Scan(&v.ID, &v.Plate, &v.Chassi, &v.Make, &v.Model, &v.Year, &v.CreatedAt); err != nil {
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
	row := r.pool.QueryRow(ctx,
		`INSERT INTO vehicles (plate, chassi, make, model, year)
		 VALUES ($1, $2, $3, $4, $5)
		 RETURNING `+selectColumns,
		NormalizePlate(input.Plate), input.Chassi, input.Make, input.Model, input.Year)

	v, err := scanVehicle(row)
	if pgErr, ok := errors.AsType[*pgconn.PgError](err); ok && pgErr.Code == uniqueViolation {
		if pgErr.ConstraintName == "vehicles_chassi_key" {
			return nil, ErrDuplicateChassi
		}
		return nil, ErrDuplicatePlate
	}
	return v, err
}
