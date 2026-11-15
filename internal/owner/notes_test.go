package owner

import (
	"context"
	"testing"
	"time"

	"connectrpc.com/connect"

	"mototeca-backend/internal/auth"
	ownerv1 "mototeca-backend/internal/gen/mototeca/owner/v1"
	"mototeca-backend/internal/note"
)

const testClientID = "5b1f9c1e-2d0a-4c55-9a47-3f6a8e0f8a11"

// fakeNotes lets testOwnerID write on testPlate only.
type fakeNotes struct {
	byID map[string]*note.Note
}

func newFakeNotes() *fakeNotes { return &fakeNotes{byID: map[string]*note.Note{}} }

func (f *fakeNotes) Add(_ context.Context, input note.AddInput, doneOn time.Time) (*note.Note, error) {
	if input.OwnerID != testOwnerID || input.Plate != testPlate {
		return nil, note.ErrNotOwned
	}
	n := &note.Note{ID: "note-" + input.ClientID, DoneOn: doneOn, Description: input.Description}
	f.byID[n.ID] = n
	return n, nil
}

func (f *fakeNotes) Delete(_ context.Context, ownerID, id string) (*string, error) {
	n, ok := f.byID[id]
	if !ok || ownerID != testOwnerID {
		return nil, note.ErrNotFound
	}
	delete(f.byID, id)
	return n.PhotoURL, nil
}

func (f *fakeNotes) FindOwned(context.Context, string, string) (*note.Note, error) { return nil, nil }
func (f *fakeNotes) SetPhoto(context.Context, string, string, string) error        { return nil }
func (f *fakeNotes) ListByPlate(context.Context, string, int) ([]note.Note, error) {
	return nil, nil
}

type fakePhotos struct{ deleted []string }

func (f *fakePhotos) Delete(_ context.Context, url string) error {
	f.deleted = append(f.deleted, url)
	return nil
}

func validNoteRequest() *ownerv1.AddMaintenanceNoteRequest {
	return &ownerv1.AddMaintenanceNoteRequest{
		Plate:       "abc-1d23",
		ClientId:    testClientID,
		DoneOn:      "2026-10-03",
		Description: "Troca de óleo em casa",
	}
}

func asOwner() context.Context { return auth.WithOwnerID(context.Background(), testOwnerID) }

func TestAddMaintenanceNote(t *testing.T) {
	h := newTestHandler(t, newFakeStore(), &fakeRecords{})

	res, err := h.AddMaintenanceNote(asOwner(), connect.NewRequest(validNoteRequest()))
	if err != nil {
		t.Fatalf("AddMaintenanceNote: %v", err)
	}
	if res.Msg.Note.DoneOn != "2026-10-03" {
		t.Errorf("doneOn = %q, want 2026-10-03", res.Msg.Note.DoneOn)
	}

	_, err = h.AddMaintenanceNote(context.Background(), connect.NewRequest(validNoteRequest()))
	assertConnectCode(t, err, connect.CodeUnauthenticated)
}

// Someone else's bike and an unknown plate get the same answer.
func TestAddMaintenanceNoteOnABikeYouDoNotOwn(t *testing.T) {
	h := newTestHandler(t, newFakeStore(), &fakeRecords{})
	req := validNoteRequest()
	req.Plate = "XYZ9Z99"

	_, err := h.AddMaintenanceNote(asOwner(), connect.NewRequest(req))
	assertConnectCode(t, err, connect.CodeNotFound)
}

func TestAddMaintenanceNoteValidatesInput(t *testing.T) {
	tomorrowPlusOne := time.Now().AddDate(0, 0, 2).Format(note.DateLayout)
	km := -1
	for name, change := range map[string]func(*ownerv1.AddMaintenanceNoteRequest){
		"no description":   func(r *ownerv1.AddMaintenanceNoteRequest) { r.Description = "  " },
		"future day":       func(r *ownerv1.AddMaintenanceNoteRequest) { r.DoneOn = tomorrowPlusOne },
		"not a day":        func(r *ownerv1.AddMaintenanceNoteRequest) { r.DoneOn = "03/10/2026" },
		"no client id":     func(r *ownerv1.AddMaintenanceNoteRequest) { r.ClientId = "" },
		"negative mileage": func(r *ownerv1.AddMaintenanceNoteRequest) { r.MileageKm = new(int32(km)) },
	} {
		t.Run(name, func(t *testing.T) {
			h := newTestHandler(t, newFakeStore(), &fakeRecords{})
			req := validNoteRequest()
			change(req)
			_, err := h.AddMaintenanceNote(asOwner(), connect.NewRequest(req))
			assertConnectCode(t, err, connect.CodeInvalidArgument)
		})
	}
}

func TestDeleteMaintenanceNoteRemovesItsPhoto(t *testing.T) {
	notes := newFakeNotes()
	photo := "http://storage/bucket/notes/note-1/a.jpg"
	notes.byID["note-1"] = &note.Note{ID: "note-1", PhotoURL: &photo}
	photos := &fakePhotos{}
	h := newTestHandler(t, newFakeStore(), &fakeRecords{})
	h.notes, h.photos = notes, photos

	if _, err := h.DeleteMaintenanceNote(asOwner(),
		connect.NewRequest(&ownerv1.DeleteMaintenanceNoteRequest{Id: "note-1"})); err != nil {
		t.Fatalf("DeleteMaintenanceNote: %v", err)
	}
	if len(photos.deleted) != 1 || photos.deleted[0] != photo {
		t.Errorf("deleted photos = %v, want [%s]", photos.deleted, photo)
	}

	_, err := h.DeleteMaintenanceNote(asOwner(),
		connect.NewRequest(&ownerv1.DeleteMaintenanceNoteRequest{Id: "note-1"}))
	assertConnectCode(t, err, connect.CodeNotFound)
}
