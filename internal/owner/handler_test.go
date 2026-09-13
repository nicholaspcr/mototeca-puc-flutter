package owner

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	"connectrpc.com/connect"

	"mototeca-backend/internal/auth"
	ownerv1 "mototeca-backend/internal/gen/mototeca/owner/v1"
	"mototeca-backend/internal/servicerecord"
)

const (
	testOwnerID   = "owner-1"
	testPhone     = "31990001234"
	validPassword = "senha-forte-123"
	testPlate     = "ABC1D23"
)

type fakeStore struct {
	byPhone    map[string]*Owner
	vehicles   map[string][]OwnedVehicle
	claimErr   error
	releaseErr error
}

func newFakeStore() *fakeStore {
	return &fakeStore{byPhone: map[string]*Owner{}, vehicles: map[string][]OwnedVehicle{}}
}

func (f *fakeStore) FindByPhone(_ context.Context, phone string) (*Owner, error) {
	return f.byPhone[phone], nil
}

func (f *fakeStore) Create(_ context.Context, input CreateInput, passwordHash string) (*Owner, error) {
	phone := NormalizePhone(input.Phone)
	if _, exists := f.byPhone[phone]; exists {
		return nil, ErrDuplicatePhone
	}
	o := &Owner{
		ID:           "owner-" + phone,
		Name:         input.Name,
		Phone:        phone,
		PasswordHash: passwordHash,
		CreatedAt:    time.Now(),
	}
	f.byPhone[phone] = o
	return o, nil
}

func (f *fakeStore) ListVehicles(_ context.Context, ownerID string) ([]OwnedVehicle, error) {
	return f.vehicles[ownerID], nil
}

func (f *fakeStore) Release(_ context.Context, ownerID, plate string) error {
	if f.releaseErr != nil {
		return f.releaseErr
	}
	f.vehicles[ownerID] = nil
	return nil
}

func (f *fakeStore) Claim(_ context.Context, ownerID, plate string) (*OwnedVehicle, error) {
	if f.claimErr != nil {
		return nil, f.claimErr
	}
	v := OwnedVehicle{
		Vehicle: servicerecord.VehicleSummary{
			Plate: plate, Make: "Honda", Model: "CG 160 Start", Year: 2022,
		},
	}
	f.vehicles[ownerID] = append(f.vehicles[ownerID], v)
	return &v, nil
}

// fakeRecords satisfies servicerecord.Store; only FindByID is exercised here.
type fakeRecords struct{ record *servicerecord.ServiceRecord }

func (f *fakeRecords) Create(context.Context, servicerecord.CreateInput) (*servicerecord.ServiceRecord, error) {
	return nil, errors.New("not used")
}
func (f *fakeRecords) Revise(context.Context, string, string, servicerecord.CreateInput) (*servicerecord.ServiceRecord, error) {
	return nil, errors.New("not used")
}
func (f *fakeRecords) FindByID(context.Context, string) (*servicerecord.ServiceRecord, error) {
	return f.record, nil
}
func (f *fakeRecords) ListByPlate(context.Context, string, int) (*servicerecord.VehicleSummary, []servicerecord.ServiceRecord, error) {
	return nil, nil, nil
}
func (f *fakeRecords) ListByWorkshop(context.Context, string, int) ([]servicerecord.ServiceRecord, error) {
	return nil, nil
}
func (f *fakeRecords) AddAttachment(context.Context, string, string, servicerecord.Attachment) (*servicerecord.Attachment, error) {
	return nil, errors.New("not used")
}
func (f *fakeRecords) CountByWorkshopSince(context.Context, string, time.Time) (int, error) {
	return 0, nil
}

func newTestHandler(t *testing.T, store Store, records servicerecord.Store) *Handler {
	t.Helper()
	signer, err := auth.NewSigner("test-secret-that-is-long-enough-32ch", time.Hour)
	if err != nil {
		t.Fatalf("NewSigner: %v", err)
	}
	return NewHandler(store, records, signer, slog.New(slog.NewTextHandler(io.Discard, nil)))
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

func TestCreateOwner(t *testing.T) {
	store := newFakeStore()
	h := newTestHandler(t, store, &fakeRecords{})

	res, err := h.CreateOwner(context.Background(), connect.NewRequest(&ownerv1.CreateOwnerRequest{
		Name:     "Marcos Souza",
		Phone:    "(31) 99000-1234",
		Password: validPassword,
	}))
	if err != nil {
		t.Fatalf("CreateOwner: %v", err)
	}

	if res.Msg.Owner.Phone != testPhone {
		t.Errorf("phone = %q, want the punctuation stripped (%q)", res.Msg.Owner.Phone, testPhone)
	}
	if res.Msg.Token == "" {
		t.Error("expected a session token so signup goes straight to Minhas Motos")
	}

	stored := store.byPhone[testPhone]
	if stored.PasswordHash == validPassword {
		t.Fatal("the plaintext password was stored instead of a digest")
	}
	if !auth.CheckPassword(stored.PasswordHash, validPassword) {
		t.Error("stored digest does not verify against the original password")
	}
}

func TestCreateOwnerRejectsInvalidInput(t *testing.T) {
	cases := map[string]*ownerv1.CreateOwnerRequest{
		"blank name":       {Name: "  ", Phone: testPhone, Password: validPassword},
		"short phone":      {Name: "Marcos", Phone: "3199", Password: validPassword},
		"mobile without 9": {Name: "Marcos", Phone: "31890001234", Password: validPassword},
		"short password":   {Name: "Marcos", Phone: testPhone, Password: "curta"},
	}

	for name, req := range cases {
		t.Run(name, func(t *testing.T) {
			h := newTestHandler(t, newFakeStore(), &fakeRecords{})
			_, err := h.CreateOwner(context.Background(), connect.NewRequest(req))
			assertConnectCode(t, err, connect.CodeInvalidArgument)
		})
	}
}

func TestCreateOwnerRejectsDuplicatePhone(t *testing.T) {
	h := newTestHandler(t, newFakeStore(), &fakeRecords{})
	req := &ownerv1.CreateOwnerRequest{Name: "Marcos", Phone: testPhone, Password: validPassword}

	if _, err := h.CreateOwner(context.Background(), connect.NewRequest(req)); err != nil {
		t.Fatalf("first CreateOwner: %v", err)
	}
	_, err := h.CreateOwner(context.Background(), connect.NewRequest(req))
	assertConnectCode(t, err, connect.CodeAlreadyExists)
}

func TestLogin(t *testing.T) {
	h := newTestHandler(t, newFakeStore(), &fakeRecords{})
	if _, err := h.CreateOwner(context.Background(), connect.NewRequest(&ownerv1.CreateOwnerRequest{
		Name: "Marcos Souza", Phone: testPhone, Password: validPassword,
	})); err != nil {
		t.Fatalf("CreateOwner: %v", err)
	}

	res, err := h.Login(context.Background(), connect.NewRequest(&ownerv1.LoginRequest{
		Phone: "(31) 99000-1234", Password: validPassword,
	}))
	if err != nil {
		t.Fatalf("Login: %v", err)
	}
	if res.Msg.Token == "" || res.Msg.Owner.Name != "Marcos Souza" {
		t.Errorf("unexpected login response: %+v", res.Msg)
	}
}

// An unknown phone and a wrong password must be indistinguishable.
func TestLoginFailuresAreIndistinguishable(t *testing.T) {
	h := newTestHandler(t, newFakeStore(), &fakeRecords{})
	if _, err := h.CreateOwner(context.Background(), connect.NewRequest(&ownerv1.CreateOwnerRequest{
		Name: "Marcos", Phone: testPhone, Password: validPassword,
	})); err != nil {
		t.Fatalf("CreateOwner: %v", err)
	}

	_, wrongPassword := h.Login(context.Background(), connect.NewRequest(&ownerv1.LoginRequest{
		Phone: testPhone, Password: "senha-errada-123",
	}))
	_, unknownPhone := h.Login(context.Background(), connect.NewRequest(&ownerv1.LoginRequest{
		Phone: "31988887777", Password: validPassword,
	}))

	assertConnectCode(t, wrongPassword, connect.CodeUnauthenticated)
	assertConnectCode(t, unknownPhone, connect.CodeUnauthenticated)
	if wrongPassword.Error() != unknownPhone.Error() {
		t.Errorf("messages differ and leak which phones are registered:\n  %v\n  %v",
			wrongPassword, unknownPhone)
	}
}

func TestListMyVehiclesRequiresOwnerAuth(t *testing.T) {
	h := newTestHandler(t, newFakeStore(), &fakeRecords{})

	_, anonymous := h.ListMyVehicles(context.Background(),
		connect.NewRequest(&ownerv1.ListMyVehiclesRequest{}))
	assertConnectCode(t, anonymous, connect.CodeUnauthenticated)

	// A workshop is authenticated, but not as an owner.
	_, asWorkshop := h.ListMyVehicles(auth.WithWorkshopID(context.Background(), "workshop-1"),
		connect.NewRequest(&ownerv1.ListMyVehiclesRequest{}))
	assertConnectCode(t, asWorkshop, connect.CodeUnauthenticated)
}

func TestListMyVehiclesIncludesReminderAndLastService(t *testing.T) {
	store := newFakeStore()
	lastOil := 15000
	lastID := "record-1"
	store.vehicles[testOwnerID] = []OwnedVehicle{{
		Vehicle: servicerecord.VehicleSummary{
			Plate: testPlate, Make: "Honda", Model: "CG 160 Start", Year: 2022,
		},
		CurrentMileageKm: 17600,
		ServiceCount:     3,
		LastServiceID:    &lastID,
		LastOilChangeKm:  &lastOil,
	}}
	records := &fakeRecords{record: &servicerecord.ServiceRecord{
		ID:           lastID,
		WorkshopName: "Oficina do Zé",
		Operations:   []servicerecord.Operation{servicerecord.OperationOilChange},
		MileageKm:    15000,
		CreatedAt:    time.Now(),
	}}
	h := newTestHandler(t, store, records)

	res, err := h.ListMyVehicles(auth.WithOwnerID(context.Background(), testOwnerID),
		connect.NewRequest(&ownerv1.ListMyVehiclesRequest{}))
	if err != nil {
		t.Fatalf("ListMyVehicles: %v", err)
	}

	got := res.Msg.Vehicles[0]
	if got.Vehicle.Plate != testPlate {
		t.Errorf("plate = %q, want %q", got.Vehicle.Plate, testPlate)
	}
	// 15000 + 3000 interval - 17600 current = 400 km left, inside the warning band.
	if got.Reminder != "Troca de óleo em 400 km" || !got.ReminderIsDue {
		t.Errorf("reminder = %q (due=%v), want the 400 km warning", got.Reminder, got.ReminderIsDue)
	}
	if got.LastService == nil || got.LastService.WorkshopName != "Oficina do Zé" {
		t.Error("expected the last service to be embedded")
	}
}

func TestClaimVehicle(t *testing.T) {
	store := newFakeStore()
	h := newTestHandler(t, store, &fakeRecords{})

	res, err := h.ClaimVehicle(auth.WithOwnerID(context.Background(), testOwnerID),
		connect.NewRequest(&ownerv1.ClaimVehicleRequest{Plate: "abc-1d23"}))
	if err != nil {
		t.Fatalf("ClaimVehicle: %v", err)
	}
	if res.Msg.Vehicle.Vehicle.Plate != testPlate {
		t.Errorf("plate = %q, want it normalized to %q", res.Msg.Vehicle.Vehicle.Plate, testPlate)
	}
}

func TestClaimVehicleErrors(t *testing.T) {
	cases := map[error]connect.Code{
		ErrVehicleNotFound: connect.CodeNotFound,
		ErrVehicleClaimed:  connect.CodeFailedPrecondition,
	}

	for storeErr, want := range cases {
		store := newFakeStore()
		store.claimErr = storeErr
		h := newTestHandler(t, store, &fakeRecords{})

		_, err := h.ClaimVehicle(auth.WithOwnerID(context.Background(), testOwnerID),
			connect.NewRequest(&ownerv1.ClaimVehicleRequest{Plate: testPlate}))
		assertConnectCode(t, err, want)
	}
}

func TestReleaseVehicle(t *testing.T) {
	h := newTestHandler(t, newFakeStore(), &fakeRecords{})

	if _, err := h.ReleaseVehicle(auth.WithOwnerID(context.Background(), testOwnerID),
		connect.NewRequest(&ownerv1.ReleaseVehicleRequest{Plate: testPlate})); err != nil {
		t.Fatalf("ReleaseVehicle: %v", err)
	}
}

func TestReleaseVehicleRequiresOwnerAuth(t *testing.T) {
	h := newTestHandler(t, newFakeStore(), &fakeRecords{})
	_, err := h.ReleaseVehicle(context.Background(),
		connect.NewRequest(&ownerv1.ReleaseVehicleRequest{Plate: testPlate}))
	assertConnectCode(t, err, connect.CodeUnauthenticated)
}

func TestReleaseVehicleRejectsABikeYouDoNotOwn(t *testing.T) {
	store := newFakeStore()
	store.releaseErr = ErrVehicleNotFound
	h := newTestHandler(t, store, &fakeRecords{})

	_, err := h.ReleaseVehicle(auth.WithOwnerID(context.Background(), testOwnerID),
		connect.NewRequest(&ownerv1.ReleaseVehicleRequest{Plate: testPlate}))
	assertConnectCode(t, err, connect.CodeNotFound)
}

func TestReminder(t *testing.T) {
	km := func(v int) *int { return &v }

	cases := map[string]struct {
		vehicle  OwnedVehicle
		wantText string
		wantDue  bool
	}{
		"never serviced": {
			vehicle:  OwnedVehicle{},
			wantText: "Sem serviços registrados",
		},
		"serviced but no oil change": {
			vehicle:  OwnedVehicle{ServiceCount: 2, CurrentMileageKm: 9000},
			wantText: "Sem troca de óleo registrada",
			wantDue:  true,
		},
		"comfortably in date": {
			vehicle:  OwnedVehicle{CurrentMileageKm: 15500, LastOilChangeKm: km(15000), ServiceCount: 1},
			wantText: "Em dia · próxima troca em 2500 km",
		},
		"due soon": {
			vehicle:  OwnedVehicle{CurrentMileageKm: 17600, LastOilChangeKm: km(15000), ServiceCount: 1},
			wantText: "Troca de óleo em 400 km",
			wantDue:  true,
		},
		"overdue": {
			vehicle:  OwnedVehicle{CurrentMileageKm: 18500, LastOilChangeKm: km(15000), ServiceCount: 1},
			wantText: "Troca de óleo atrasada em 500 km",
			wantDue:  true,
		},
	}

	for name, tc := range cases {
		t.Run(name, func(t *testing.T) {
			got := tc.vehicle.Reminder()
			if got.Text != tc.wantText || got.IsDue != tc.wantDue {
				t.Errorf("Reminder() = %q (due=%v), want %q (due=%v)",
					got.Text, got.IsDue, tc.wantText, tc.wantDue)
			}
		})
	}
}

func TestNormalizePhone(t *testing.T) {
	for raw, want := range map[string]string{
		"(31) 99000-1234":   testPhone,
		"31990001234":       testPhone,
		"+55 31 99000 1234": "5531990001234",
		"abc":               "",
	} {
		if got := NormalizePhone(raw); got != want {
			t.Errorf("NormalizePhone(%q) = %q, want %q", raw, got, want)
		}
	}
}
