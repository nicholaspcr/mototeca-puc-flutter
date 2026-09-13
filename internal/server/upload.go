package server

import (
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"mototeca-backend/internal/auth"
	"mototeca-backend/internal/servicerecord"
	"mototeca-backend/internal/storage"
)

// UploadHandler serves multipart photo uploads.
//
// Not a Connect RPC: protobuf would carry the bytes base64-encoded, inflating
// every photo by a third and holding it all in memory. A plain multipart POST
// streams instead, and reuses the same bearer token.
type UploadHandler struct {
	store   *storage.Store
	records servicerecord.Store
	signer  *auth.Signer
	logger  *slog.Logger
}

func NewUploadHandler(store *storage.Store, records servicerecord.Store, signer *auth.Signer, logger *slog.Logger) *UploadHandler {
	return &UploadHandler{store: store, records: records, signer: signer, logger: logger}
}

// phaseParams maps the form value to what attachments.phase accepts.
var phaseParams = map[string]string{
	"before": servicerecord.PhaseBefore,
	"after":  servicerecord.PhaseAfter,
}

func (h *UploadHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	workshopID, ok := h.authenticate(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "workshop authentication required")
		return
	}

	recordID := r.PathValue("id")
	if recordID == "" {
		writeError(w, http.StatusBadRequest, "invalid_argument", "record id is required")
		return
	}

	// Refuse an over-sized body before reading it, not after.
	r.Body = http.MaxBytesReader(w, r.Body, storage.MaxPhotoBytes+1<<20)
	if err := r.ParseMultipartForm(storage.MaxPhotoBytes); err != nil {
		writeError(w, http.StatusRequestEntityTooLarge, "invalid_argument",
			fmt.Sprintf("arquivo acima do limite de %d MiB", storage.MaxPhotoBytes>>20))
		return
	}
	defer func() { _ = r.MultipartForm.RemoveAll() }()

	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_argument", "campo \"file\" é obrigatório")
		return
	}
	defer func() { _ = file.Close() }()

	kind := r.FormValue("kind")
	if kind == "" {
		kind = "photo"
	}
	if kind != "photo" && kind != "invoice" {
		writeError(w, http.StatusBadRequest, "invalid_argument", "kind deve ser \"photo\" ou \"invoice\"")
		return
	}

	var phase *string
	if raw := r.FormValue("phase"); raw != "" {
		mapped, valid := phaseParams[raw]
		if !valid {
			writeError(w, http.StatusBadRequest, "invalid_argument", "phase deve ser \"before\" ou \"after\"")
			return
		}
		if kind != "photo" {
			writeError(w, http.StatusBadRequest, "invalid_argument", "só fotos têm antes/depois")
			return
		}
		phase = &mapped
	}

	// The declared type is not trusted: storage checks it against its
	// allowlist and the name is generated there, never taken from the client.
	contentType := header.Header.Get("Content-Type")
	url, err := h.store.Put(r.Context(), recordID, contentType, header.Size, file)
	if errors.Is(err, storage.ErrUnsupportedType) {
		writeError(w, http.StatusBadRequest, "invalid_argument",
			"tipo não suportado; envie "+strings.Join(storage.SupportedTypes(), ", "))
		return
	}
	if err != nil {
		h.logger.ErrorContext(r.Context(), "storing upload failed", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "falha ao guardar o arquivo")
		return
	}

	stored, err := h.records.AddAttachment(r.Context(), workshopID, recordID,
		servicerecord.Attachment{URL: url, Kind: kind, Phase: phase})
	if errors.Is(err, servicerecord.ErrRecordNotFound) {
		writeError(w, http.StatusNotFound, "not_found", "service record not found")
		return
	}
	if err != nil {
		h.logger.ErrorContext(r.Context(), "linking attachment failed", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "falha ao vincular o arquivo")
		return
	}

	// Same spelling the RPCs use, so the client has one representation to
	// parse rather than two.
	writeJSON(w, http.StatusOK, map[string]any{
		"id":    stored.ID,
		"url":   stored.URL,
		"kind":  stored.Kind,
		"phase": wirePhase(stored.Phase),
	})
}

func wirePhase(phase *string) *string {
	if phase == nil {
		return nil
	}
	wire := "PHOTO_PHASE_" + strings.ToUpper(*phase)
	return &wire
}

func (h *UploadHandler) authenticate(r *http.Request) (string, bool) {
	token, ok := bearerToken(r.Header.Get("Authorization"))
	if !ok {
		return "", false
	}
	subject, err := h.signer.Verify(token, time.Now())
	if err != nil || subject.Kind != auth.KindWorkshop {
		return "", false
	}
	return subject.ID, true
}

func bearerToken(header string) (string, bool) {
	scheme, token, found := strings.Cut(header, " ")
	if !found || !strings.EqualFold(scheme, "Bearer") {
		return "", false
	}
	token = strings.TrimSpace(token)
	return token, token != ""
}

// writeError matches Connect's error body, so the Flutter client parses
// failures from this route exactly as it does from every RPC.
func writeError(w http.ResponseWriter, status int, code, message string) {
	writeJSON(w, status, map[string]string{"code": code, "message": message})
}

func writeJSON(w http.ResponseWriter, status int, body any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(body)
}
