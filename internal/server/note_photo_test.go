package server

import (
	"context"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"testing"

	"mototeca-backend/internal/auth"
	"mototeca-backend/internal/note"
)

const (
	photoNoteID = "7c9e6679-7425-40de-944b-e07fc1f90ae7"
	photoOwner  = "owner-1"
)

// fakeNoteStore holds one note that photoOwner may attach a photo to.
type fakeNoteStore struct {
	note.Store
	note *note.Note
}

func (f *fakeNoteStore) FindOwned(_ context.Context, ownerID, id string) (*note.Note, error) {
	if ownerID != photoOwner || id != f.note.ID {
		return nil, nil
	}
	return f.note, nil
}

func (f *fakeNoteStore) SetPhoto(_ context.Context, _, _, url string) error {
	if f.note.PhotoURL != nil {
		return note.ErrPhotoExists
	}
	f.note.PhotoURL = &url
	return nil
}

func serveNotePhoto(t *testing.T, notes *fakeNoteStore, objects *fakeObjects, kind auth.Kind, id string, content []byte) *httptest.ResponseRecorder {
	t.Helper()
	f := newUploadFixture(t)
	handler := NewNotePhotoHandler(objects, notes, f.signer, slog.New(slog.NewTextHandler(io.Discard, nil)))
	mux := http.NewServeMux()
	mux.Handle("POST /v1/maintenance-notes/{id}/photo", handler)

	body, contentType := multipartBody(t, "image/png", content, nil)
	req := httptest.NewRequest(http.MethodPost, "/v1/maintenance-notes/"+photoNoteID+"/photo", body)
	req.Header.Set("Content-Type", contentType)
	req.Header.Set("Authorization", "Bearer "+f.token(t, kind, id))
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

func TestNotePhotoIsStoredOnce(t *testing.T) {
	notes := &fakeNoteStore{note: &note.Note{ID: photoNoteID}}
	objects := &fakeObjects{}

	assertStatus(t, serveNotePhoto(t, notes, objects, auth.KindOwner, photoOwner, onePixelPNG), http.StatusOK)
	if notes.note.PhotoURL == nil {
		t.Fatal("photo URL not saved on the note")
	}

	// A retry after a lost response is told the photo is already there.
	assertStatus(t, serveNotePhoto(t, notes, objects, auth.KindOwner, photoOwner, onePixelPNG), http.StatusConflict)
}

func TestNotePhotoRefusals(t *testing.T) {
	for name, tc := range map[string]struct {
		kind    auth.Kind
		id      string
		content []byte
		want    int
	}{
		"workshop token":      {auth.KindWorkshop, photoOwner, onePixelPNG, http.StatusUnauthorized},
		"someone else's note": {auth.KindOwner, "owner-2", onePixelPNG, http.StatusNotFound},
		"not an image":        {auth.KindOwner, photoOwner, []byte("%PDF-1.4 fake"), http.StatusBadRequest},
	} {
		t.Run(name, func(t *testing.T) {
			notes := &fakeNoteStore{note: &note.Note{ID: photoNoteID}}
			objects := &fakeObjects{}
			assertStatus(t, serveNotePhoto(t, notes, objects, tc.kind, tc.id, tc.content), tc.want)
			if objects.putType != "" {
				t.Error("a file was stored for a refused upload")
			}
		})
	}
}
