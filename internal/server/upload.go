package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"net/http"
	"strings"
	"time"

	"mototeca-backend/internal/auth"
	"mototeca-backend/internal/servicerecord"
	"mototeca-backend/internal/storage"
)

// uploadDeadline replaces the server's short read and write timeouts on this
// route: a phone photo over a shop's weak connection takes far longer than an
// RPC body. It matches the Flutter client's upload timeout.
const uploadDeadline = 60 * time.Second

// ObjectStore is the upload route's view of object storage.
type ObjectStore interface {
	Put(ctx context.Context, prefix, contentType string, size int64, body io.Reader) (string, error)
	Delete(ctx context.Context, url string) error
}

// UploadHandler serves multipart photo uploads.
//
// Not a Connect RPC: protobuf would carry the bytes base64-encoded, inflating
// every photo by a third and holding it all in memory. A plain multipart POST
// streams instead, and reuses the same bearer token.
type UploadHandler struct {
	store   ObjectStore
	records servicerecord.Store
	signer  *auth.Signer
	logger  *slog.Logger
}

func NewUploadHandler(store ObjectStore, records servicerecord.Store, signer *auth.Signer, logger *slog.Logger) *UploadHandler {
	return &UploadHandler{store: store, records: records, signer: signer, logger: logger}
}

// phaseParams maps the form value to what attachments.phase accepts.
var phaseParams = map[string]string{
	"before": servicerecord.PhaseBefore,
	"after":  servicerecord.PhaseAfter,
}

func (h *UploadHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	ctx := r.Context()

	workshopID, ok := h.authenticate(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, "unauthenticated", "entre como oficina para continuar")
		return
	}

	// Ownership is checked before the body is read, so nobody streams a file
	// at a record they cannot attach to.
	record, err := h.records.FindByID(ctx, r.PathValue("id"))
	if err != nil {
		h.logger.ErrorContext(ctx, "loading record for upload failed", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "falha ao enviar o arquivo")
		return
	}
	if record == nil || record.WorkshopID != workshopID {
		writeError(w, http.StatusNotFound, "not_found", "registro não encontrado")
		return
	}

	rc := http.NewResponseController(w)
	_ = rc.SetReadDeadline(time.Now().Add(uploadDeadline))
	_ = rc.SetWriteDeadline(time.Now().Add(uploadDeadline))

	r.Body = http.MaxBytesReader(w, r.Body, storage.MaxPhotoBytes+1<<20)
	if err := r.ParseMultipartForm(storage.MaxPhotoBytes); err != nil {
		if _, tooLarge := errors.AsType[*http.MaxBytesError](err); tooLarge {
			writeError(w, http.StatusRequestEntityTooLarge, "invalid_argument",
				fmt.Sprintf("arquivo acima do limite de %d MiB", storage.MaxPhotoBytes>>20))
			return
		}
		writeError(w, http.StatusBadRequest, "invalid_argument", "envie o arquivo como multipart/form-data")
		return
	}
	defer func() { _ = r.MultipartForm.RemoveAll() }()

	kind, phase, message := attachmentKind(r.FormValue("kind"), r.FormValue("phase"))
	if message != "" {
		writeError(w, http.StatusBadRequest, "invalid_argument", message)
		return
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_argument", "campo \"file\" é obrigatório")
		return
	}
	defer func() { _ = file.Close() }()

	// The client's declared type is ignored: the type is read from the bytes,
	// so an HTML page labelled image/png is refused rather than served back.
	contentType, err := sniffContentType(file)
	if err != nil {
		writeError(w, http.StatusBadRequest, "invalid_argument", "não foi possível ler o arquivo")
		return
	}

	url, err := h.store.Put(ctx, record.ID, contentType, header.Size, file)
	if errors.Is(err, storage.ErrUnsupportedType) {
		writeError(w, http.StatusBadRequest, "invalid_argument",
			"tipo não suportado; envie "+strings.Join(storage.SupportedTypes(), ", "))
		return
	}
	if err != nil {
		h.logger.ErrorContext(ctx, "storing upload failed", "err", err)
		writeError(w, http.StatusInternalServerError, "internal", "falha ao guardar o arquivo")
		return
	}

	stored, err := h.records.AddAttachment(ctx, workshopID, record.ID,
		servicerecord.Attachment{URL: url, Kind: kind, Phase: phase})
	if err != nil {
		h.removeOrphan(ctx, url)
		if errors.Is(err, servicerecord.ErrRecordNotFound) {
			writeError(w, http.StatusNotFound, "not_found", "registro não encontrado")
			return
		}
		h.logger.ErrorContext(ctx, "linking attachment failed", "err", err)
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

// attachmentKind validates the form fields, returning a user-facing message
// when they are wrong.
func attachmentKind(kind, rawPhase string) (string, *string, string) {
	if kind == "" {
		kind = "photo"
	}
	if kind != "photo" && kind != "invoice" {
		return "", nil, "kind deve ser \"photo\" ou \"invoice\""
	}
	if rawPhase == "" {
		return kind, nil, ""
	}

	phase, valid := phaseParams[rawPhase]
	if !valid {
		return "", nil, "phase deve ser \"before\" ou \"after\""
	}
	if kind != "photo" {
		return "", nil, "só fotos têm antes/depois"
	}
	return kind, &phase, ""
}

// sniffContentType reads the first bytes to detect the type, then rewinds.
func sniffContentType(file io.ReadSeeker) (string, error) {
	head := make([]byte, 512)
	n, err := io.ReadFull(file, head)
	if err != nil && !errors.Is(err, io.ErrUnexpectedEOF) {
		return "", err
	}
	if _, err := file.Seek(0, io.SeekStart); err != nil {
		return "", err
	}
	return http.DetectContentType(head[:n]), nil
}

// removeOrphan deletes a stored file whose attachment row was never written.
// It outlives the request, which may already be cancelled.
func (h *UploadHandler) removeOrphan(ctx context.Context, url string) {
	if err := h.store.Delete(context.WithoutCancel(ctx), url); err != nil {
		h.logger.ErrorContext(ctx, "removing orphaned upload failed", "err", err, "url", url)
	}
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
