// Package auth holds the workshop credential and session-token primitives
// shared by the workshop and service-record domains.
package auth

import (
	"fmt"
	"unicode/utf8"

	"golang.org/x/crypto/bcrypt"
)

// MinPasswordLength is enforced on signup. bcrypt silently truncates past 72
// bytes, so anything longer is rejected rather than quietly shortened.
const (
	MinPasswordLength = 8
	maxPasswordBytes  = 72
)

// ValidatePassword reports whether a plaintext password is acceptable to store.
func ValidatePassword(plain string) error {
	if utf8.RuneCountInString(plain) < MinPasswordLength {
		return fmt.Errorf("password must be at least %d characters", MinPasswordLength)
	}
	if len(plain) > maxPasswordBytes {
		return fmt.Errorf("password must be at most %d bytes", maxPasswordBytes)
	}
	return nil
}

// HashPassword returns the bcrypt digest to store for a plaintext password.
func HashPassword(plain string) (string, error) {
	if err := ValidatePassword(plain); err != nil {
		return "", err
	}
	digest, err := bcrypt.GenerateFromPassword([]byte(plain), bcrypt.DefaultCost)
	if err != nil {
		return "", fmt.Errorf("hashing password: %w", err)
	}
	return string(digest), nil
}

// CheckPassword reports whether plain matches the stored digest. It is
// deliberately boolean: callers must not distinguish "no such user" from
// "wrong password" in what they return to the client.
func CheckPassword(digest, plain string) bool {
	if digest == "" {
		return false
	}
	return bcrypt.CompareHashAndPassword([]byte(digest), []byte(plain)) == nil
}
