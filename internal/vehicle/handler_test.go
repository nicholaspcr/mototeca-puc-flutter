package vehicle

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	"connectrpc.com/connect"

	vehiclev1 "mototeca-backend/internal/gen/mototeca/vehicle/v1"
)

// fakeStore is an in-memory Store used to unit test Handler without a
// database.
type fakeStore struct {
	vehicles  map[string]*Vehicle
	findErr   error
	createErr error
	created   *Vehicle
}

func (f *fakeStore) FindByPlate(_ context.Context, plate string) (*Vehicle, error) {
	if f.findErr != nil {
		return nil, f.findErr
	}
	return f.vehicles[plate], nil
}

func (f *fakeStore) Create(_ context.Context, input CreateInput) (*Vehicle, error) {
	if f.createErr != nil {
		return nil, f.createErr
	}
	v := &Vehicle{
		ID:        "generated-id",
		Plate:     NormalizePlate(input.Plate),
		Chassi:    input.Chassi,
		Make:      input.Make,
		Model:     input.Model,
		Year:      input.Year,
		CreatedAt: time.Now(),
	}
	f.created = v
	return v, nil
}

func discardLogger() *slog.Logger {
	return slog.New(slog.NewTextHandler(io.Discard, nil))
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
		t.Errorf("code = %v, want %v", connectErr.Code(), want)
	}
}

func TestHandlerGetVehicleByPlate(t *testing.T) {
	t.Run("empty plate is invalid argument", func(t *testing.T) {
		h := NewHandler(&fakeStore{}, discardLogger())
		_, err := h.GetVehicleByPlate(context.Background(), connect.NewRequest(&vehiclev1.GetVehicleByPlateRequest{Plate: ""}))
		assertConnectCode(t, err, connect.CodeInvalidArgument)
	})

	t.Run("not found", func(t *testing.T) {
		h := NewHandler(&fakeStore{vehicles: map[string]*Vehicle{}}, discardLogger())
		_, err := h.GetVehicleByPlate(context.Background(), connect.NewRequest(&vehiclev1.GetVehicleByPlateRequest{Plate: "ABC1D23"}))
		assertConnectCode(t, err, connect.CodeNotFound)
	})

	t.Run("store error becomes internal", func(t *testing.T) {
		h := NewHandler(&fakeStore{findErr: errors.New("boom")}, discardLogger())
		_, err := h.GetVehicleByPlate(context.Background(), connect.NewRequest(&vehiclev1.GetVehicleByPlateRequest{Plate: "ABC1D23"}))
		assertConnectCode(t, err, connect.CodeInternal)
	})

	t.Run("found", func(t *testing.T) {
		want := &Vehicle{
			ID: "1", Plate: "ABC1D23", Chassi: "9BWZZZ377VT004251",
			Make: "Honda", Model: "CG 160", Year: 2022, CreatedAt: time.Now(),
		}
		h := NewHandler(&fakeStore{vehicles: map[string]*Vehicle{"ABC1D23": want}}, discardLogger())
		resp, err := h.GetVehicleByPlate(context.Background(), connect.NewRequest(&vehiclev1.GetVehicleByPlateRequest{Plate: "abc1d23"}))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if resp.Msg.Vehicle.Plate != "ABC1D23" {
			t.Errorf("Plate = %q, want ABC1D23", resp.Msg.Vehicle.Plate)
		}
	})
}

func TestHandlerCreateVehicle(t *testing.T) {
	validReq := &vehiclev1.CreateVehicleRequest{
		Plate:  "ABC1D23",
		Chassi: "9BWZZZ377VT004251",
		Make:   "Honda",
		Model:  "CG 160",
		Year:   2022,
	}

	t.Run("invalid input", func(t *testing.T) {
		h := NewHandler(&fakeStore{}, discardLogger())
		bad := &vehiclev1.CreateVehicleRequest{
			Plate:  "XYZ",
			Chassi: validReq.Chassi,
			Make:   validReq.Make,
			Model:  validReq.Model,
			Year:   validReq.Year,
		}
		_, err := h.CreateVehicle(context.Background(), connect.NewRequest(bad))
		assertConnectCode(t, err, connect.CodeInvalidArgument)
	})

	t.Run("store error becomes internal", func(t *testing.T) {
		h := NewHandler(&fakeStore{createErr: errors.New("boom")}, discardLogger())
		_, err := h.CreateVehicle(context.Background(), connect.NewRequest(validReq))
		assertConnectCode(t, err, connect.CodeInternal)
	})

	t.Run("success", func(t *testing.T) {
		store := &fakeStore{}
		h := NewHandler(store, discardLogger())
		resp, err := h.CreateVehicle(context.Background(), connect.NewRequest(validReq))
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if resp.Msg.Vehicle.Plate != "ABC1D23" {
			t.Errorf("Plate = %q, want ABC1D23", resp.Msg.Vehicle.Plate)
		}
		if store.created == nil {
			t.Fatal("expected Create to be called on store")
		}
	})
}

func BenchmarkToProto(b *testing.B) {
	ownerID := "owner-1"
	v := &Vehicle{
		ID:             "1",
		Plate:          "ABC1D23",
		Chassi:         "9BWZZZ377VT004251",
		Make:           "Honda",
		Model:          "CG 160 Start",
		Year:           2022,
		CurrentOwnerID: &ownerID,
		CreatedAt:      time.Now(),
	}
	for b.Loop() {
		toProto(v)
	}
}
