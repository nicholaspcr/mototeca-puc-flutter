package servicerecord

import (
	"context"
	"errors"
	"io"
	"log/slog"
	"testing"
	"time"

	"connectrpc.com/connect"

	"mototeca-backend/internal/auth"
	servicev1 "mototeca-backend/internal/gen/mototeca/service/v1"
)

const (
	testWorkshopID = "workshop-1"
	testPlate      = "ABC1D23"
)

type fakeStore struct {
	records    map[string]*ServiceRecord
	byPlate    map[string]*VehicleSummary
	createErr  error
	listErr    error
	created    *CreateInput
	countMonth int
	lastLimit  int
	reviseErr  error
}

func newFakeStore() *fakeStore {
	return &fakeStore{
		records: map[string]*ServiceRecord{},
		byPlate: map[string]*VehicleSummary{
			testPlate: {Plate: testPlate, Make: "Honda", Model: "CG 160 Start", Year: 2022},
		},
	}
}

func (f *fakeStore) Create(_ context.Context, input CreateInput) (*ServiceRecord, error) {
	if f.createErr != nil {
		return nil, f.createErr
	}
	summary, ok := f.byPlate[input.Plate]
	if !ok {
		return nil, ErrVehicleNotFound
	}
	f.created = &input
	record := &ServiceRecord{
		ID:           "record-1",
		Vehicle:      *summary,
		WorkshopName: "Oficina do Zé",
		MechanicName: input.MechanicName,
		Operations:   input.Operations,
		MileageKm:    input.MileageKm,
		CostCents:    input.CostCents,
		Notes:        input.Notes,
		Parts:        input.Parts,
		CreatedAt:    time.Now(),
	}
	f.records[record.ID] = record
	return record, nil
}

func (f *fakeStore) Revise(_ context.Context, workshopID, recordID string, input CreateInput) (*ServiceRecord, error) {
	if f.reviseErr != nil {
		return nil, f.reviseErr
	}
	f.created = &input
	revised := &ServiceRecord{ID: "record-2", RevisesRecordID: &recordID, Operations: input.Operations}
	f.records[revised.ID] = revised
	return revised, nil
}

func (f *fakeStore) FindByID(_ context.Context, id string) (*ServiceRecord, error) {
	return f.records[id], nil
}

func (f *fakeStore) ListByPlate(_ context.Context, plate string, limit int) (*VehicleSummary, []ServiceRecord, error) {
	f.lastLimit = limit
	if f.listErr != nil {
		return nil, nil, f.listErr
	}
	summary, ok := f.byPlate[plate]
	if !ok {
		return nil, nil, nil
	}
	var records []ServiceRecord
	for _, r := range f.records {
		if r.Vehicle.Plate == plate {
			records = append(records, *r)
		}
	}
	return summary, records, nil
}

func (f *fakeStore) ListByWorkshop(_ context.Context, _ string, limit int) ([]ServiceRecord, error) {
	if f.listErr != nil {
		return nil, f.listErr
	}
	var records []ServiceRecord
	for _, r := range f.records {
		if len(records) == limit {
			break
		}
		records = append(records, *r)
	}
	return records, nil
}

func (f *fakeStore) CountByWorkshopSince(_ context.Context, _ string, _ time.Time) (int, error) {
	return f.countMonth, nil
}

func newTestHandler(store Store) *Handler {
	return NewHandler(store, slog.New(slog.NewTextHandler(io.Discard, nil)))
}

func authedContext() context.Context {
	return auth.WithWorkshopID(context.Background(), testWorkshopID)
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

func validCreateRequest() *servicev1.CreateServiceRecordRequest {
	mechanic := "José Carlos"
	cost := int32(24500)
	return &servicev1.CreateServiceRecordRequest{
		Plate:        "abc-1d23",
		MechanicName: &mechanic,
		Operations: []servicev1.ServiceType{
			servicev1.ServiceType_SERVICE_TYPE_OIL_CHANGE,
			servicev1.ServiceType_SERVICE_TYPE_CHAIN_AND_SPROCKET,
		},
		MileageKm: 18420,
		CostCents: &cost,
	}
}

func TestCreateServiceRecord(t *testing.T) {
	store := newFakeStore()
	h := newTestHandler(store)

	res, err := h.CreateServiceRecord(authedContext(), connect.NewRequest(validCreateRequest()))
	if err != nil {
		t.Fatalf("CreateServiceRecord: %v", err)
	}

	if got := len(res.Msg.Record.Operations); got != 2 {
		t.Errorf("operations = %d, want 2 — a record carries every operation ticked", got)
	}
	if store.created.Plate != testPlate {
		t.Errorf("stored plate = %q, want it normalized to %q", store.created.Plate, testPlate)
	}
	if store.created.WorkshopID != testWorkshopID {
		t.Errorf("workshop = %q, want the one from the session (%q)", store.created.WorkshopID, testWorkshopID)
	}
}

// The workshop must come from the token, never the request, or one shop could
// write history under another shop's name.
func TestCreateServiceRecordRequiresAuthentication(t *testing.T) {
	h := newTestHandler(newFakeStore())
	_, err := h.CreateServiceRecord(context.Background(), connect.NewRequest(validCreateRequest()))
	assertConnectCode(t, err, connect.CodeUnauthenticated)
}

func TestCreateServiceRecordRejectsInvalidInput(t *testing.T) {
	negative := int32(-1)
	cases := map[string]func(*servicev1.CreateServiceRecordRequest){
		"no operations": func(r *servicev1.CreateServiceRecordRequest) { r.Operations = nil },
		"unspecified operation": func(r *servicev1.CreateServiceRecordRequest) {
			r.Operations = []servicev1.ServiceType{servicev1.ServiceType_SERVICE_TYPE_UNSPECIFIED}
		},
		"duplicate operation": func(r *servicev1.CreateServiceRecordRequest) {
			r.Operations = []servicev1.ServiceType{
				servicev1.ServiceType_SERVICE_TYPE_TIRES,
				servicev1.ServiceType_SERVICE_TYPE_TIRES,
			}
		},
		"negative mileage": func(r *servicev1.CreateServiceRecordRequest) { r.MileageKm = -5 },
		"absurd mileage":   func(r *servicev1.CreateServiceRecordRequest) { r.MileageKm = 9_000_000 },
		"negative cost":    func(r *servicev1.CreateServiceRecordRequest) { r.CostCents = &negative },
		"blank part name": func(r *servicev1.CreateServiceRecordRequest) {
			r.Parts = []*servicev1.Part{{Name: "  ", Quantity: 1}}
		},
		"zero part quantity": func(r *servicev1.CreateServiceRecordRequest) {
			r.Parts = []*servicev1.Part{{Name: "Óleo", Quantity: 0}}
		},
	}

	for name, mutate := range cases {
		t.Run(name, func(t *testing.T) {
			req := validCreateRequest()
			mutate(req)
			h := newTestHandler(newFakeStore())
			_, err := h.CreateServiceRecord(authedContext(), connect.NewRequest(req))
			assertConnectCode(t, err, connect.CodeInvalidArgument)
		})
	}
}

func TestCreateServiceRecordRejectsUnknownPlate(t *testing.T) {
	h := newTestHandler(newFakeStore())
	req := validCreateRequest()
	req.Plate = "ZZZ9Z99"

	_, err := h.CreateServiceRecord(authedContext(), connect.NewRequest(req))
	assertConnectCode(t, err, connect.CodeNotFound)
}

func TestListServiceRecordsByPlateIsPublic(t *testing.T) {
	store := newFakeStore()
	h := newTestHandler(store)
	if _, err := h.CreateServiceRecord(authedContext(), connect.NewRequest(validCreateRequest())); err != nil {
		t.Fatalf("CreateServiceRecord: %v", err)
	}

	// No workshop in the context: this is the no-account lookup.
	res, err := h.ListServiceRecordsByPlate(context.Background(),
		connect.NewRequest(&servicev1.ListServiceRecordsByPlateRequest{Plate: "abc1d23"}))
	if err != nil {
		t.Fatalf("ListServiceRecordsByPlate: %v", err)
	}
	if len(res.Msg.Records) != 1 {
		t.Fatalf("records = %d, want 1", len(res.Msg.Records))
	}
	if res.Msg.Vehicle.Plate != testPlate {
		t.Errorf("plate = %q, want %q", res.Msg.Vehicle.Plate, testPlate)
	}
}

func TestListServiceRecordsByPlateRejectsUnknownPlate(t *testing.T) {
	h := newTestHandler(newFakeStore())
	_, err := h.ListServiceRecordsByPlate(context.Background(),
		connect.NewRequest(&servicev1.ListServiceRecordsByPlateRequest{Plate: "ZZZ9Z99"}))
	assertConnectCode(t, err, connect.CodeNotFound)
}

func TestListWorkshopServiceRecordsRequiresAuthentication(t *testing.T) {
	h := newTestHandler(newFakeStore())
	_, err := h.ListWorkshopServiceRecords(context.Background(),
		connect.NewRequest(&servicev1.ListWorkshopServiceRecordsRequest{}))
	assertConnectCode(t, err, connect.CodeUnauthenticated)
}

func TestListWorkshopServiceRecordsReportsMonthlyCount(t *testing.T) {
	store := newFakeStore()
	store.countMonth = 7
	h := newTestHandler(store)

	res, err := h.ListWorkshopServiceRecords(authedContext(),
		connect.NewRequest(&servicev1.ListWorkshopServiceRecordsRequest{}))
	if err != nil {
		t.Fatalf("ListWorkshopServiceRecords: %v", err)
	}
	if res.Msg.CountThisMonth != 7 {
		t.Errorf("countThisMonth = %d, want 7", res.Msg.CountThisMonth)
	}
}

// The public lookup must not let a caller ask for an unbounded page.
func TestListLimitIsClamped(t *testing.T) {
	for requested, want := range map[int32]int{
		0:      defaultListLimit,
		-1:     defaultListLimit,
		10:     10,
		100000: maxListLimit,
	} {
		if got := clampLimit(requested); got != want {
			t.Errorf("clampLimit(%d) = %d, want %d", requested, got, want)
		}
	}
}

func TestListByPlatePassesTheClampedLimit(t *testing.T) {
	store := newFakeStore()
	h := newTestHandler(store)

	if _, err := h.ListServiceRecordsByPlate(context.Background(),
		connect.NewRequest(&servicev1.ListServiceRecordsByPlateRequest{
			Plate: testPlate, Limit: 100000,
		})); err != nil {
		t.Fatalf("ListServiceRecordsByPlate: %v", err)
	}
	if store.lastLimit != maxListLimit {
		t.Errorf("limit reaching the store = %d, want it capped at %d", store.lastLimit, maxListLimit)
	}
}

func validReviseRequest() *servicev1.ReviseServiceRecordRequest {
	return &servicev1.ReviseServiceRecordRequest{
		RecordId:   "record-1",
		Operations: []servicev1.ServiceType{servicev1.ServiceType_SERVICE_TYPE_TIRES},
		MileageKm:  18500,
	}
}

func seedRecord(t *testing.T, h *Handler) *fakeStore {
	t.Helper()
	store, ok := h.repo.(*fakeStore)
	if !ok {
		t.Fatal("expected a fakeStore")
	}
	if _, err := h.CreateServiceRecord(authedContext(), connect.NewRequest(validCreateRequest())); err != nil {
		t.Fatalf("CreateServiceRecord: %v", err)
	}
	return store
}

func TestReviseServiceRecord(t *testing.T) {
	h := newTestHandler(newFakeStore())
	store := seedRecord(t, h)

	res, err := h.ReviseServiceRecord(authedContext(), connect.NewRequest(validReviseRequest()))
	if err != nil {
		t.Fatalf("ReviseServiceRecord: %v", err)
	}
	if res.Msg.Record.RevisesRecordId == nil || *res.Msg.Record.RevisesRecordId != "record-1" {
		t.Errorf("revisesRecordId = %v, want record-1", res.Msg.Record.RevisesRecordId)
	}
	// A correction stays on the same bike as the record it replaces.
	if store.created.Plate != testPlate {
		t.Errorf("plate = %q, want it taken from the original (%q)", store.created.Plate, testPlate)
	}
}

func TestReviseServiceRecordRequiresAuthentication(t *testing.T) {
	h := newTestHandler(newFakeStore())
	_, err := h.ReviseServiceRecord(context.Background(), connect.NewRequest(validReviseRequest()))
	assertConnectCode(t, err, connect.CodeUnauthenticated)
}

func TestReviseServiceRecordErrors(t *testing.T) {
	t.Run("unknown record", func(t *testing.T) {
		h := newTestHandler(newFakeStore())
		_, err := h.ReviseServiceRecord(authedContext(), connect.NewRequest(validReviseRequest()))
		assertConnectCode(t, err, connect.CodeNotFound)
	})

	t.Run("already superseded", func(t *testing.T) {
		h := newTestHandler(newFakeStore())
		store := seedRecord(t, h)
		store.reviseErr = ErrAlreadySuperseded

		_, err := h.ReviseServiceRecord(authedContext(), connect.NewRequest(validReviseRequest()))
		assertConnectCode(t, err, connect.CodeFailedPrecondition)
	})

	t.Run("another workshop's record", func(t *testing.T) {
		h := newTestHandler(newFakeStore())
		store := seedRecord(t, h)
		store.reviseErr = ErrRecordNotFound

		_, err := h.ReviseServiceRecord(authedContext(), connect.NewRequest(validReviseRequest()))
		assertConnectCode(t, err, connect.CodeNotFound)
	})

	t.Run("invalid correction", func(t *testing.T) {
		h := newTestHandler(newFakeStore())
		seedRecord(t, h)
		req := validReviseRequest()
		req.Operations = nil

		_, err := h.ReviseServiceRecord(authedContext(), connect.NewRequest(req))
		assertConnectCode(t, err, connect.CodeInvalidArgument)
	})
}

func TestGetServiceRecordNotFound(t *testing.T) {
	h := newTestHandler(newFakeStore())
	_, err := h.GetServiceRecord(context.Background(),
		connect.NewRequest(&servicev1.GetServiceRecordRequest{Id: "nope"}))
	assertConnectCode(t, err, connect.CodeNotFound)
}

// Every taxonomy entry must survive the domain -> wire -> domain trip, or a
// record would come back describing a different repair than it stored.
func TestOperationProtoMappingIsTotal(t *testing.T) {
	for op := range validOperations {
		wire := operationToProto(op)
		if wire == servicev1.ServiceType_SERVICE_TYPE_UNSPECIFIED {
			t.Errorf("operation %q has no wire value", op)
			continue
		}
		if back := operationFromProto(wire); back != op {
			t.Errorf("round trip of %q produced %q", op, back)
		}
	}
}
