package workshop

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"strings"
	"testing"
	"time"

	"connectrpc.com/connect"

	"mototeca-backend/internal/auth"
	workshopv1 "mototeca-backend/internal/gen/mototeca/workshop/v1"
)

// validCNPJ passes the check-digit maths (11.222.333/0001-81).
const (
	validCNPJ     = "11222333000181"
	validPassword = "senha-forte-123"
)

type fakeStore struct {
	byCNPJ    map[string]*Workshop
	findErr   error
	createErr error
}

func newFakeStore() *fakeStore {
	return &fakeStore{byCNPJ: map[string]*Workshop{}}
}

func (f *fakeStore) FindByCNPJ(_ context.Context, cnpj string) (*Workshop, error) {
	if f.findErr != nil {
		return nil, f.findErr
	}
	return f.byCNPJ[cnpj], nil
}

func (f *fakeStore) FindByID(_ context.Context, id string) (*Workshop, error) {
	if f.findErr != nil {
		return nil, f.findErr
	}
	for _, w := range f.byCNPJ {
		if w.ID == id {
			return w, nil
		}
	}
	return nil, nil
}

func (f *fakeStore) Create(_ context.Context, input CreateInput, passwordHash string) (*Workshop, error) {
	if f.createErr != nil {
		return nil, f.createErr
	}
	cnpj := NormalizeCNPJ(input.CNPJ)
	if _, exists := f.byCNPJ[cnpj]; exists {
		return nil, ErrDuplicateCNPJ
	}
	w := &Workshop{
		ID:           "workshop-" + cnpj,
		CNPJ:         cnpj,
		Name:         input.Name,
		Address:      input.Address,
		PasswordHash: passwordHash,
		CreatedAt:    time.Now(),
	}
	f.byCNPJ[cnpj] = w
	return w, nil
}

func newTestHandler(t *testing.T, store Store) *Handler {
	t.Helper()
	signer, err := auth.NewSigner("test-secret-that-is-long-enough-32ch", time.Hour)
	if err != nil {
		t.Fatalf("NewSigner: %v", err)
	}
	return NewHandler(store, signer, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func assertConnectCode(t *testing.T, err error, want connect.Code) {
	t.Helper()
	if err == nil {
		t.Fatalf("expected error with code %v, got nil", want)
	}
	var connectErr *connect.Error
	if !errors.As(err, &connectErr) {
		t.Fatalf("expected *connect.Error, got %T: %v", err, err)
	}
	if connectErr.Code() != want {
		t.Fatalf("code = %v, want %v", connectErr.Code(), want)
	}
}

func TestCreateWorkshop(t *testing.T) {
	store := newFakeStore()
	h := newTestHandler(t, store)

	res, err := h.CreateWorkshop(context.Background(), connect.NewRequest(&workshopv1.CreateWorkshopRequest{
		Cnpj:     "11.222.333/0001-81",
		Name:     "Oficina do Zé",
		Password: validPassword,
	}))
	if err != nil {
		t.Fatalf("CreateWorkshop: %v", err)
	}

	if got := res.Msg.Workshop.Cnpj; got != validCNPJ {
		t.Errorf("cnpj = %q, want the punctuation stripped (%q)", got, validCNPJ)
	}
	if res.Msg.Token == "" {
		t.Error("expected a session token so signup lands on the dashboard")
	}

	stored := store.byCNPJ[validCNPJ]
	if stored.PasswordHash == validPassword {
		t.Fatal("the plaintext password was stored instead of a digest")
	}
	if !auth.CheckPassword(stored.PasswordHash, validPassword) {
		t.Error("stored digest does not verify against the original password")
	}
}

func TestCreateWorkshopRejectsInvalidInput(t *testing.T) {
	cases := map[string]*workshopv1.CreateWorkshopRequest{
		"bad check digits": {Cnpj: "11222333000199", Name: "Oficina", Password: validPassword},
		"too few digits":   {Cnpj: "1122233300", Name: "Oficina", Password: validPassword},
		"repeated digits":  {Cnpj: "11111111111111", Name: "Oficina", Password: validPassword},
		"blank name":       {Cnpj: validCNPJ, Name: "   ", Password: validPassword},
		"short password":   {Cnpj: validCNPJ, Name: "Oficina", Password: "curta"},
	}

	for name, req := range cases {
		t.Run(name, func(t *testing.T) {
			h := newTestHandler(t, newFakeStore())
			_, err := h.CreateWorkshop(context.Background(), connect.NewRequest(req))
			assertConnectCode(t, err, connect.CodeInvalidArgument)
		})
	}
}

func TestCreateWorkshopRejectsDuplicateCNPJ(t *testing.T) {
	store := newFakeStore()
	h := newTestHandler(t, store)
	req := &workshopv1.CreateWorkshopRequest{Cnpj: validCNPJ, Name: "Oficina", Password: validPassword}

	if _, err := h.CreateWorkshop(context.Background(), connect.NewRequest(req)); err != nil {
		t.Fatalf("first CreateWorkshop: %v", err)
	}

	_, err := h.CreateWorkshop(context.Background(), connect.NewRequest(req))
	assertConnectCode(t, err, connect.CodeAlreadyExists)
}

func TestLogin(t *testing.T) {
	store := newFakeStore()
	h := newTestHandler(t, store)
	if _, err := h.CreateWorkshop(context.Background(), connect.NewRequest(&workshopv1.CreateWorkshopRequest{
		Cnpj: validCNPJ, Name: "Oficina do Zé", Password: validPassword,
	})); err != nil {
		t.Fatalf("CreateWorkshop: %v", err)
	}

	res, err := h.Login(context.Background(), connect.NewRequest(&workshopv1.LoginRequest{
		Cnpj: "11.222.333/0001-81", Password: validPassword,
	}))
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if res.Msg.Token == "" {
		t.Error("expected a session token")
	}
	if res.Msg.Workshop.Name != "Oficina do Zé" {
		t.Errorf("name = %q, want %q", res.Msg.Workshop.Name, "Oficina do Zé")
	}
}

// An unknown CNPJ and a wrong password must be indistinguishable, or the
// endpoint becomes a way to discover which shops are registered.
func TestLoginFailuresAreIndistinguishable(t *testing.T) {
	store := newFakeStore()
	h := newTestHandler(t, store)
	if _, err := h.CreateWorkshop(context.Background(), connect.NewRequest(&workshopv1.CreateWorkshopRequest{
		Cnpj: validCNPJ, Name: "Oficina", Password: validPassword,
	})); err != nil {
		t.Fatalf("CreateWorkshop: %v", err)
	}

	_, wrongPassword := h.Login(context.Background(), connect.NewRequest(&workshopv1.LoginRequest{
		Cnpj: validCNPJ, Password: "senha-errada-123",
	}))
	_, unknownCNPJ := h.Login(context.Background(), connect.NewRequest(&workshopv1.LoginRequest{
		Cnpj: "11444777000161", Password: validPassword,
	}))

	assertConnectCode(t, wrongPassword, connect.CodeUnauthenticated)
	assertConnectCode(t, unknownCNPJ, connect.CodeUnauthenticated)
	if wrongPassword.Error() != unknownCNPJ.Error() {
		t.Errorf("messages differ and leak which CNPJs exist:\n  wrong password: %v\n  unknown cnpj:   %v",
			wrongPassword, unknownCNPJ)
	}
}

// Guesses spread across many addresses still lock the one account, and the
// right password does not get through while it is locked.
func TestLoginLocksAnAccountAfterRepeatedFailures(t *testing.T) {
	h := newTestHandler(t, newFakeStore())
	if _, err := h.CreateWorkshop(context.Background(), connect.NewRequest(&workshopv1.CreateWorkshopRequest{
		Cnpj: validCNPJ, Name: "Oficina", Password: validPassword,
	})); err != nil {
		t.Fatalf("CreateWorkshop: %v", err)
	}

	login := func(password string) error {
		_, err := h.Login(context.Background(), connect.NewRequest(&workshopv1.LoginRequest{
			Cnpj: validCNPJ, Password: password,
		}))
		return err
	}

	for range auth.LoginFailureLimit {
		assertConnectCode(t, login("senha-errada-123"), connect.CodeUnauthenticated)
	}
	assertConnectCode(t, login(validPassword), connect.CodeResourceExhausted)
}

func TestLoginRejectsEmptyCredentials(t *testing.T) {
	h := newTestHandler(t, newFakeStore())
	_, err := h.Login(context.Background(), connect.NewRequest(&workshopv1.LoginRequest{}))
	assertConnectCode(t, err, connect.CodeUnauthenticated)
}

func TestNormalizeCNPJ(t *testing.T) {
	for raw, want := range map[string]string{
		"11.222.333/0001-81":  validCNPJ,
		"11222333000181":      validCNPJ,
		" 11 222 333 0001 81": validCNPJ,
		"abc":                 "",
	} {
		if got := NormalizeCNPJ(raw); got != want {
			t.Errorf("NormalizeCNPJ(%q) = %q, want %q", raw, got, want)
		}
	}
}

func TestValidateCNPJ(t *testing.T) {
	valid := []string{validCNPJ, "11444777000161"}
	for _, cnpj := range valid {
		if err := ValidateCNPJ(cnpj); err != nil {
			t.Errorf("ValidateCNPJ(%q) = %v, want nil", cnpj, err)
		}
	}

	invalid := []string{"", "1122233300018", strings.Repeat("1", 14), "11222333000180"}
	for _, cnpj := range invalid {
		if err := ValidateCNPJ(cnpj); err == nil {
			t.Errorf("ValidateCNPJ(%q) = nil, want an error", cnpj)
		}
	}
}
