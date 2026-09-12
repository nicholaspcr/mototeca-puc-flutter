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

// Kind is the sort of account a token belongs to. It is part of the signed
// payload, so an owner's token can never be replayed as a workshop's: the two
// flows have different powers (a workshop writes history, an owner only reads
// their own bikes).
type Kind string

const (
	KindWorkshop Kind = "w"
	KindOwner    Kind = "o"
)

func (k Kind) valid() bool { return k == KindWorkshop || k == KindOwner }

// Subject is who a verified token identifies.
type Subject struct {
	Kind Kind
	ID   string
}

// Signer issues and verifies session tokens.
//
// A token is `<payload>.<signature>`, both base64url, where payload is
// "<kind>:<id>:<expiryUnix>" and signature is HMAC-SHA256 of the payload.
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

// Issue returns a token identifying subject, valid for the signer's TTL.
func (s *Signer) Issue(subject Subject, now time.Time) (string, error) {
	if !subject.Kind.valid() {
		return "", errors.New("unknown subject kind")
	}
	if subject.ID == "" {
		return "", errors.New("subject id is required")
	}
	// ':' separates the fields, so an id containing one would let a crafted id
	// shift the expiry field.
	if strings.Contains(subject.ID, ":") {
		return "", errors.New("subject id must not contain ':'")
	}

	payload := fmt.Appendf(nil, "%s:%s:%d", subject.Kind, subject.ID, now.Add(s.ttl).Unix())
	enc := base64.RawURLEncoding
	return enc.EncodeToString(payload) + "." + enc.EncodeToString(s.sign(payload)), nil
}

// Verify returns the subject carried by a valid, unexpired token.
func (s *Signer) Verify(token string, now time.Time) (Subject, error) {
	rawPayload, rawSignature, found := strings.Cut(token, ".")
	if !found {
		return Subject{}, ErrInvalidToken
	}

	enc := base64.RawURLEncoding
	payload, err := enc.DecodeString(rawPayload)
	if err != nil {
		return Subject{}, ErrInvalidToken
	}
	signature, err := enc.DecodeString(rawSignature)
	if err != nil {
		return Subject{}, ErrInvalidToken
	}

	// Constant-time: a byte-by-byte compare leaks how much of a forged
	// signature was correct.
	if !hmac.Equal(signature, s.sign(payload)) {
		return Subject{}, ErrInvalidToken
	}

	fields := strings.Split(string(payload), ":")
	if len(fields) != 3 {
		return Subject{}, ErrInvalidToken
	}

	subject := Subject{Kind: Kind(fields[0]), ID: fields[1]}
	if !subject.Kind.valid() || subject.ID == "" {
		return Subject{}, ErrInvalidToken
	}

	expiry, err := strconv.ParseInt(fields[2], 10, 64)
	if err != nil {
		return Subject{}, ErrInvalidToken
	}
	if now.After(time.Unix(expiry, 0)) {
		return Subject{}, ErrInvalidToken
	}

	return subject, nil
}
