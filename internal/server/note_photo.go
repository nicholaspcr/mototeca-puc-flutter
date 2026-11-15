package server

import (
	"errors"
	"log/slog"
	"net/http"
	"strings"

	"mototeca-backend/internal/auth"
	"mototeca-backend/internal/note"
	"mototeca-backend/internal/storage"
)

// NotePhotoHandler stores the one photo an owner attaches to a note.
type NotePhotoHandler struct {
	store  ObjectStore
	notes  note.Store
	signer *auth.Signer
	logger *slog.Logger
}

func NewNotePhotoHandler(store ObjectStore, notes note.Store, signer *auth.Signer, logger *slog.Logger) *NotePhotoHandler {
	return &NotePhotoHandler{store: store, notes: notes, signer: signer, logger: logger}
}

func (h *NotePhotoHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	ownerID, ok := authenticate(h.signer, r, auth.KindOwner)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "entre na sua conta para continuar")
		return
	}

	found, err := h.notes.FindOwned(ctx, ownerID, r.PathValue("id"))
	if err != nil {
		h.logger.ErrorContext(ctx, "loading note for photo failed", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "falha ao enviar a foto")
		return
	}
	if found == nil {
		writeError(w, http.StatusNotFound, "not_found", "anotação não encontrada")
		return
	}
	if found.PhotoURL != nil {
		writePhotoExists(w)
		return
	}

	upload, ok := readUpload(w, r)
	if !ok {
		return
	}
	defer upload.close()

	notPhoto := func() {
		writeError(w, http.StatusBadRequest, "invalid_argument", "envie uma foto (JPEG, PNG ou WebP)")
	}
	if !strings.HasPrefix(upload.contentType, "image/") {
		notPhoto()
		return
	}

	url, err := h.store.Put(ctx, "notes/"+found.ID, upload.contentType, upload.size, upload.file)
	if errors.Is(err, storage.ErrUnsupportedType) {
		notPhoto()
		return
	}
	if err != nil {
		h.logger.ErrorContext(ctx, "storing note photo failed", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "falha ao guardar a foto")
		return
	}

	err = h.notes.SetPhoto(ctx, ownerID, found.ID, url)
	if err != nil {
		removeOrphan(ctx, h.store, h.logger, url)
		switch {
		case errors.Is(err, note.ErrPhotoExists):
			writePhotoExists(w)
		case errors.Is(err, note.ErrNotFound):
			writeError(w, http.StatusNotFound, "not_found", "anotação não encontrada")
		default:
			h.logger.ErrorContext(ctx, "linking note photo failed", "err", err)
			writeError(w, http.StatusInternalServerError, "internal", "falha ao vincular a foto")
		}
		return
	}

	writeJSON(w, http.StatusOK, map[string]string{"photoUrl": url})
}

// writePhotoExists answers a retry whose first attempt already landed.
func writePhotoExists(w http.ResponseWriter) {
	writeError(w, http.StatusConflict, "already_exists", "esta anotação já tem foto")
}
