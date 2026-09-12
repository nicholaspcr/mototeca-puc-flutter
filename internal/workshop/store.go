package workshop

import (
	"context"
	"errors"
)

// ErrDuplicateCNPJ is returned by Create when the CNPJ is already registered.
var ErrDuplicateCNPJ = errors.New("cnpj already registered")

// Store is the storage contract Handler depends on. Repository is the
// Postgres-backed implementation; tests substitute an in-memory fake.
type Store interface {
	// FindByCNPJ returns nil, nil when no workshop is registered under it.
	FindByCNPJ(ctx context.Context, cnpj string) (*Workshop, error)
	FindByID(ctx context.Context, id string) (*Workshop, error)
	// Create stores the already-hashed password; plaintext never reaches here.
	Create(ctx context.Context, input CreateInput, passwordHash string) (*Workshop, error)
}

var _ Store = (*Repository)(nil)
