package owner

import (
	"context"
	"errors"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

// uniqueViolation is Postgres' SQLSTATE for a duplicate key.
const uniqueViolation = "23505"

type Repository struct {
	pool *pgxpool.Pool
}

func NewRepository(pool *pgxpool.Pool) *Repository {
	return &Repository{pool: pool}
}

const selectColumns = `id, name, phone, cpf_hash, COALESCE(password_hash, ''), created_at`

func scanOwner(row pgx.Row) (*Owner, error) {
	var o Owner
	if err := row.Scan(&o.ID, &o.Name, &o.Phone, &o.CPFHash, &o.PasswordHash, &o.CreatedAt); err != nil {
		return nil, err
	}
	return &o, nil
}

func (r *Repository) FindByPhone(ctx context.Context, phone string) (*Owner, error) {
	row := r.pool.QueryRow(ctx, `SELECT `+selectColumns+` FROM owners WHERE phone = $1`, phone)

	o, err := scanOwner(row)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return o, nil
}

func (r *Repository) Create(ctx context.Context, input CreateInput, passwordHash string) (*Owner, error) {
	row := r.pool.QueryRow(ctx,
		`INSERT INTO owners (name, phone, password_hash)
		 VALUES ($1, $2, $3)
		 RETURNING `+selectColumns,
		input.Name, NormalizePhone(input.Phone), passwordHash)

	o, err := scanOwner(row)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == uniqueViolation {
		return nil, ErrDuplicatePhone
	}
	if err != nil {
		return nil, err
	}
	return o, nil
}

// ownedVehicleQuery derives the whole owner screen in one pass: odometer
// (highest mileage any workshop recorded), service count, newest record, and
// the mileage at the last oil change.
const ownedVehicleQuery = `
	SELECT v.plate, v.make, v.model, v.year,
	       COALESCE(MAX(sr.mileage_km), 0) AS current_km,
	       COUNT(sr.id) AS service_count,
	       (SELECT id FROM service_records
	         WHERE vehicle_id = v.id ORDER BY created_at DESC LIMIT 1) AS last_service_id,
	       (SELECT MAX(oil.mileage_km) FROM service_records oil
	          JOIN service_record_operations op ON op.service_record_id = oil.id
	         WHERE oil.vehicle_id = v.id AND op.type = 'oil_change') AS last_oil_change_km
	FROM vehicles v
	LEFT JOIN service_records sr ON sr.vehicle_id = v.id`

func scanOwnedVehicles(rows pgx.Rows) ([]OwnedVehicle, error) {
	defer rows.Close()

	var owned []OwnedVehicle
	for rows.Next() {
		var v OwnedVehicle
		if err := rows.Scan(
			&v.Vehicle.Plate, &v.Vehicle.Make, &v.Vehicle.Model, &v.Vehicle.Year,
			&v.CurrentMileageKm, &v.ServiceCount, &v.LastServiceID, &v.LastOilChangeKm,
		); err != nil {
			return nil, err
		}
		owned = append(owned, v)
	}
	return owned, rows.Err()
}

func (r *Repository) ListVehicles(ctx context.Context, ownerID string) ([]OwnedVehicle, error) {
	rows, err := r.pool.Query(ctx,
		ownedVehicleQuery+`
		 WHERE v.current_owner_id = $1
		 GROUP BY v.id
		 ORDER BY v.plate`, ownerID)
	if err != nil {
		return nil, err
	}
	return scanOwnedVehicles(rows)
}

func (r *Repository) Claim(ctx context.Context, ownerID, plate string) (*OwnedVehicle, error) {
	tx, err := r.pool.Begin(ctx)
	if err != nil {
		return nil, err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var vehicleID string
	var currentOwner *string
	err = tx.QueryRow(ctx,
		`SELECT id, current_owner_id FROM vehicles WHERE plate = $1`, plate,
	).Scan(&vehicleID, &currentOwner)
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, ErrVehicleNotFound
	}
	if err != nil {
		return nil, err
	}

	// Re-claiming your own bike is a no-op; taking someone else's is refused.
	// Transfer on sale is a separate flow (ARCHITECTURE.md §3).
	if currentOwner != nil && *currentOwner != ownerID {
		return nil, ErrVehicleClaimed
	}

	if _, err := tx.Exec(ctx,
		`UPDATE vehicles SET current_owner_id = $1 WHERE id = $2`, ownerID, vehicleID); err != nil {
		return nil, err
	}

	rows, err := tx.Query(ctx, ownedVehicleQuery+` WHERE v.id = $1 GROUP BY v.id`, vehicleID)
	if err != nil {
		return nil, err
	}
	owned, err := scanOwnedVehicles(rows)
	if err != nil {
		return nil, err
	}
	if len(owned) == 0 {
		return nil, ErrVehicleNotFound
	}

	if err := tx.Commit(ctx); err != nil {
		return nil, err
	}
	return &owned[0], nil
}
