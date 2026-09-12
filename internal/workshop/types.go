package workshop

import "time"

type Workshop struct {
	ID       string  `json:"id"`
	CNPJ     string  `json:"cnpj"`
	Name     string  `json:"name"`
	Address  *string `json:"address"`
	Verified bool    `json:"verified"`
	// PasswordHash never leaves the server: json:"-" so an accidental
	// marshal of this struct cannot leak the digest.
	PasswordHash string    `json:"-"`
	CreatedAt    time.Time `json:"createdAt"`
}

type CreateInput struct {
	CNPJ     string  `json:"cnpj"`
	Name     string  `json:"name"`
	Address  *string `json:"address"`
	Password string  `json:"-"`
}
