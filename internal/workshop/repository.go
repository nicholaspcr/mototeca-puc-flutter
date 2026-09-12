package workshop

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

const selectColumns = `id, cnpj, name, address, verified, COALESCE(password_hash, ''), created_at`

func scanWorkshop(row pgx.Row) (*Workshop, error) {
	var w Workshop
	if err := row.Scan(&w.ID, &w.CNPJ, &w.Name, &w.Address, &w.Verified, &w.PasswordHash, &w.CreatedAt); err != nil {
		return nil, err
	}
	return &w, nil
}

func (r *Repository) FindByCNPJ(ctx context.Context, cnpj string) (*Workshop, error) {
	row := r.pool.QueryRow(ctx, `SELECT `+selectColumns+` FROM workshops WHERE cnpj = $1`, cnpj)
	return scanOptional(scanWorkshop(row))
}

func (r *Repository) FindByID(ctx context.Context, id string) (*Workshop, error) {
	row := r.pool.QueryRow(ctx, `SELECT `+selectColumns+` FROM workshops WHERE id = $1`, id)
	return scanOptional(scanWorkshop(row))
}

func scanOptional(w *Workshop, err error) (*Workshop, error) {
	if errors.Is(err, pgx.ErrNoRows) {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return w, nil
}

func (r *Repository) Create(ctx context.Context, input CreateInput, passwordHash string) (*Workshop, error) {
	row := r.pool.QueryRow(ctx,
		`INSERT INTO workshops (cnpj, name, address, password_hash)
		 VALUES ($1, $2, $3, $4)
		 RETURNING `+selectColumns,
		NormalizeCNPJ(input.CNPJ), input.Name, input.Address, passwordHash)

	w, err := scanWorkshop(row)
	var pgErr *pgconn.PgError
	if errors.As(err, &pgErr) && pgErr.Code == uniqueViolation {
		return nil, ErrDuplicateCNPJ
	}
	if err != nil {
		return nil, err
	}
	return w, nil
}
