package server

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"strings"
	"time"

	"mototeca-backend/internal/auth"
	"mototeca-backend/internal/servicerecord"
	"mototeca-backend/internal/storage"
)

// uploadDeadline replaces the server's short timeouts for slow photo uploads.
const uploadDeadline = 60 * time.Second

// ObjectStore is the upload route's view of object storage.
type ObjectStore interface {
	Put(ctx context.Context, prefix, contentType string, size int64, body io.Reader) (string, error)
	Delete(ctx context.Context, url string) error
}

// UploadHandler streams multipart photo uploads; base64 in protobuf would add
// a third to every photo.
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

	workshopID, ok := authenticate(h.signer, r, auth.KindWorkshop)
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

	upload, ok := readUpload(w, r)
	if !ok {
		return
	}
	defer upload.close()

	kind, phase, message := attachmentKind(r.FormValue("kind"), r.FormValue("phase"))
	if message != "" {
		writeError(w, http.StatusBadRequest, "invalid_argument", message)
		return
	}

	url, err := h.store.Put(ctx, record.ID, upload.contentType, upload.size, upload.file)
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
		removeOrphan(ctx, h.store, h.logger, url)
		if errors.Is(err, servicerecord.ErrRecordNotFound) {
			writeError(w, http.StatusNotFound, "not_found", "registro não encontrado")
			return
		}
		if errors.Is(err, servicerecord.ErrTooManyAttachments) {
			writeError(w, http.StatusBadRequest, "invalid_argument",
				fmt.Sprintf("um registro aceita até %d arquivos", servicerecord.MaxAttachmentsPerRecord))
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

// upload is the one file of a multipart request, with its sniffed type.
type upload struct {
	file        multipart.File
	size        int64
	contentType string
	form        *multipart.Form
}

func (u upload) close() {
	_ = u.file.Close()
	_ = u.form.RemoveAll()
}

// readUpload parses the multipart body and writes the error response itself
// when it cannot.
func readUpload(w http.ResponseWriter, r *http.Request) (upload, bool) {
	rc := http.NewResponseController(w)
	_ = rc.SetReadDeadline(time.Now().Add(uploadDeadline))
	_ = rc.SetWriteDeadline(time.Now().Add(uploadDeadline))

	r.Body = http.MaxBytesReader(w, r.Body, storage.MaxPhotoBytes+1<<20)
	if err := r.ParseMultipartForm(storage.MaxPhotoBytes); err != nil {
		if _, tooLarge := errors.AsType[*http.MaxBytesError](err); tooLarge {
			writeError(w, http.StatusRequestEntityTooLarge, "invalid_argument",
				fmt.Sprintf("arquivo acima do limite de %d MiB", storage.MaxPhotoBytes>>20))
			return upload{}, false
		}
		writeError(w, http.StatusBadRequest, "invalid_argument", "envie o arquivo como multipart/form-data")
		return upload{}, false
	}

	file, header, err := r.FormFile("file")
	if err != nil {
		_ = r.MultipartForm.RemoveAll()
		writeError(w, http.StatusBadRequest, "invalid_argument", "campo \"file\" é obrigatório")
		return upload{}, false
	}

	// The client's declared type is ignored: the type is read from the bytes,
	// so an HTML page labelled image/png is refused rather than served back.
	contentType, err := sniffContentType(file)
	u := upload{file: file, size: header.Size, contentType: contentType, form: r.MultipartForm}
	if err != nil {
		u.close()
		writeError(w, http.StatusBadRequest, "invalid_argument", "não foi possível ler o arquivo")
		return upload{}, false
	}
	return u, true
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

// removeOrphan deletes a stored file whose row was never written. It outlives
// the request, which may already be cancelled.
func removeOrphan(ctx context.Context, store ObjectStore, logger *slog.Logger, url string) {
	if err := store.Delete(context.WithoutCancel(ctx), url); err != nil {
		logger.ErrorContext(ctx, "removing orphaned upload failed", "err", err, "url", url)
	}
}

func wirePhase(phase *string) *string {
	if phase == nil {
		return nil
	}
	wire := "PHOTO_PHASE_" + strings.ToUpper(*phase)
	return &wire
}

// authenticate returns the caller's id when the bearer token is for kind.
func authenticate(signer *auth.Signer, r *http.Request, kind auth.Kind) (string, bool) {
	token, ok := bearerToken(r.Header.Get("Authorization"))
	if !ok {
		return "", false
	}
	subject, err := signer.Verify(token, time.Now())
	if err != nil || subject.Kind != kind {
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
