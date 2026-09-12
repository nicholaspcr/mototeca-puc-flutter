package auth

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"strconv"
	"strings"
	"time"
)

// ErrInvalidToken covers every rejection reason — malformed, wrong signature,
// expired. Callers must not tell a client which one it was.
var ErrInvalidToken = errors.New("invalid token")

// MinSecretLength keeps a trivially guessable signing key out of production.
const MinSecretLength = 32

// Signer issues and verifies workshop session tokens.
//
// A token is `<payload>.<signature>`, both base64url, where payload is
// "<workshopID>:<expiryUnix>" and signature is HMAC-SHA256 of the payload.
// It is self-contained on purpose: no session table, so verifying a request
// costs no database round-trip. The trade-off is that a token cannot be
// revoked before it expires, which is why the TTL is short.
type Signer struct {
	secret []byte
	ttl    time.Duration
}

// NewSigner fails closed on a missing or too-short secret rather than falling
// back to a default key.
func NewSigner(secret string, ttl time.Duration) (*Signer, error) {
	if len(secret) < MinSecretLength {
		return nil, fmt.Errorf("auth secret must be at least %d characters", MinSecretLength)
	}
	if ttl <= 0 {
		return nil, errors.New("auth token ttl must be positive")
	}
	return &Signer{secret: []byte(secret), ttl: ttl}, nil
}

func (s *Signer) sign(payload []byte) []byte {
	mac := hmac.New(sha256.New, s.secret)
	mac.Write(payload)
	return mac.Sum(nil)
}

// Issue returns a token identifying workshopID, valid for the signer's TTL.
func (s *Signer) Issue(workshopID string, now time.Time) (string, error) {
	if workshopID == "" {
		return "", errors.New("workshop id is required")
	}
	if strings.Contains(workshopID, ":") {
		return "", errors.New("workshop id must not contain ':'")
	}

	payload := fmt.Appendf(nil, "%s:%d", workshopID, now.Add(s.ttl).Unix())
	enc := base64.RawURLEncoding
	return enc.EncodeToString(payload) + "." + enc.EncodeToString(s.sign(payload)), nil
}

// Verify returns the workshop id carried by a valid, unexpired token.
func (s *Signer) Verify(token string, now time.Time) (string, error) {
	rawPayload, rawSignature, found := strings.Cut(token, ".")
	if !found {
		return "", ErrInvalidToken
	}

	enc := base64.RawURLEncoding
	payload, err := enc.DecodeString(rawPayload)
	if err != nil {
		return "", ErrInvalidToken
	}
	signature, err := enc.DecodeString(rawSignature)
	if err != nil {
		return "", ErrInvalidToken
	}

	// Constant-time: a byte-by-byte compare leaks how much of a forged
	// signature was correct.
	if !hmac.Equal(signature, s.sign(payload)) {
		return "", ErrInvalidToken
	}

	workshopID, rawExpiry, found := strings.Cut(string(payload), ":")
	if !found || workshopID == "" {
		return "", ErrInvalidToken
	}
	expiry, err := strconv.ParseInt(rawExpiry, 10, 64)
	if err != nil {
		return "", ErrInvalidToken
	}
	if now.After(time.Unix(expiry, 0)) {
		return "", ErrInvalidToken
	}

	return workshopID, nil
}
