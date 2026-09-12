package auth

import (
	"context"
	"errors"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"
)

const testSecret = "test-secret-that-is-long-enough-32ch"

func newTestSigner(t *testing.T, ttl time.Duration) *Signer {
	t.Helper()
	signer, err := NewSigner(testSecret, ttl)
	if err != nil {
		t.Fatalf("NewSigner: %v", err)
	}
	return signer
}

func TestNewSignerRejectsWeakConfig(t *testing.T) {
	if _, err := NewSigner("short", time.Hour); err == nil {
		t.Error("expected a short secret to be rejected")
	}
	if _, err := NewSigner(testSecret, 0); err == nil {
		t.Error("expected a non-positive ttl to be rejected")
	}
}

func TestIssueAndVerifyRoundTrip(t *testing.T) {
	signer := newTestSigner(t, time.Hour)
	now := time.Now()

	token, err := signer.Issue("workshop-1", now)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}

	got, err := signer.Verify(token, now)
	if err != nil {
		t.Fatalf("Verify: %v", err)
	}
	if got != "workshop-1" {
		t.Errorf("workshop id = %q, want %q", got, "workshop-1")
	}
}

func TestVerifyRejectsExpiredToken(t *testing.T) {
	signer := newTestSigner(t, time.Minute)
	issuedAt := time.Now()

	token, err := signer.Issue("workshop-1", issuedAt)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}

	if _, err := signer.Verify(token, issuedAt.Add(2*time.Minute)); !errors.Is(err, ErrInvalidToken) {
		t.Errorf("err = %v, want ErrInvalidToken", err)
	}
}

func TestVerifyRejectsTamperedToken(t *testing.T) {
	signer := newTestSigner(t, time.Hour)
	now := time.Now()

	token, err := signer.Issue("workshop-1", now)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	payload, signature, _ := strings.Cut(token, ".")

	// A payload swapped for another workshop keeps the original signature.
	forged, err := newTestSigner(t, time.Hour).Issue("workshop-2", now)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}
	otherPayload, _, _ := strings.Cut(forged, ".")

	for name, tampered := range map[string]string{
		"swapped payload":   otherPayload + "." + signature,
		"garbage signature": payload + ".not-base64!!",
		"missing separator": payload + signature,
		"empty":             "",
	} {
		if _, err := signer.Verify(tampered, now); !errors.Is(err, ErrInvalidToken) {
			t.Errorf("%s: err = %v, want ErrInvalidToken", name, err)
		}
	}
}

func TestVerifyRejectsTokenFromAnotherSecret(t *testing.T) {
	issuer, err := NewSigner("a-completely-different-secret-key-32", time.Hour)
	if err != nil {
		t.Fatalf("NewSigner: %v", err)
	}
	now := time.Now()

	token, err := issuer.Issue("workshop-1", now)
	if err != nil {
		t.Fatalf("Issue: %v", err)
	}

	if _, err := newTestSigner(t, time.Hour).Verify(token, now); !errors.Is(err, ErrInvalidToken) {
		t.Errorf("err = %v, want ErrInvalidToken", err)
	}
}

func TestPasswordHashingRoundTrip(t *testing.T) {
	digest, err := HashPassword("correct horse battery")
	if err != nil {
		t.Fatalf("HashPassword: %v", err)
	}
	if strings.Contains(digest, "correct horse battery") {
		t.Fatal("digest must not contain the plaintext password")
	}
	if !CheckPassword(digest, "correct horse battery") {
		t.Error("correct password was rejected")
	}
	if CheckPassword(digest, "wrong password") {
		t.Error("wrong password was accepted")
	}
	if CheckPassword("", "correct horse battery") {
		t.Error("an empty digest must never authenticate")
	}
}

func TestHashPasswordRejectsWeakPasswords(t *testing.T) {
	if _, err := HashPassword("short"); err == nil {
		t.Error("expected a too-short password to be rejected")
	}
	if _, err := HashPassword(strings.Repeat("a", 73)); err == nil {
		t.Error("expected an over-72-byte password to be rejected, not truncated")
	}
}

func TestRequireWorkshopID(t *testing.T) {
	if _, err := RequireWorkshopID(context.Background()); err == nil {
		t.Fatal("expected an error for an unauthenticated context")
	} else {
		var connectErr *connect.Error
		if !errors.As(err, &connectErr) || connectErr.Code() != connect.CodeUnauthenticated {
			t.Errorf("err = %v, want CodeUnauthenticated", err)
		}
	}

	ctx := WithWorkshopID(context.Background(), "workshop-1")
	id, err := RequireWorkshopID(ctx)
	if err != nil {
		t.Fatalf("RequireWorkshopID: %v", err)
	}
	if id != "workshop-1" {
		t.Errorf("id = %q, want %q", id, "workshop-1")
	}
}

func TestBearerToken(t *testing.T) {
	for header, want := range map[string]string{
		"Bearer abc": "abc",
		"bearer abc": "abc",
		"Basic abc":  "",
		"abc":        "",
		"Bearer ":    "",
		"":           "",
	} {
		got, ok := bearerToken(header)
		if got != want || ok != (want != "") {
			t.Errorf("bearerToken(%q) = %q, %v; want %q", header, got, ok, want)
		}
	}
}
