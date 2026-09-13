package server

import (
	"bytes"
	"context"
	"errors"
	"io"
	"log/slog"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"net/textproto"
	"testing"
	"time"

	"mototeca-backend/internal/auth"
	"mototeca-backend/internal/servicerecord"
	"mototeca-backend/internal/storage"
)

const (
	uploadRecordID = "0e04cd56-7eac-4bc5-a137-83dea52dceae"
	uploadWorkshop = "workshop-1"
)

// onePixelPNG is a complete PNG, so content sniffing sees real image bytes.
var onePixelPNG = []byte("\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde\x00\x00\x00\x0cIDATx\x9cc\xf8\x0f\x04\x00\x09\xfb\x03\xfd\xe3U\xf2\xb1\x00\x00\x00\x00IEND\xaeB`\x82")

type fakeObjects struct {
	putType string
	deleted []string
}

func (f *fakeObjects) Put(_ context.Context, prefix, contentType string, _ int64, body io.Reader) (string, error) {
	if _, err := io.ReadAll(body); err != nil {
		return "", err
	}
	if contentType != "image/png" && contentType != "image/jpeg" {
		return "", storage.ErrUnsupportedType
	}
	f.putType = contentType
	return "http://storage/bucket/" + prefix + "/file.png", nil
}

func (f *fakeObjects) Delete(_ context.Context, url string) error {
	f.deleted = append(f.deleted, url)
	return nil
}

// fakeRecords implements the two methods the upload route uses.
type fakeRecords struct {
	servicerecord.Store
	record    *servicerecord.ServiceRecord
	attachErr error
}

func (f *fakeRecords) FindByID(context.Context, string) (*servicerecord.ServiceRecord, error) {
	return f.record, nil
}

func (f *fakeRecords) AddAttachment(_ context.Context, _, _ string, a servicerecord.Attachment) (*servicerecord.Attachment, error) {
	if f.attachErr != nil {
		return nil, f.attachErr
	}
	a.ID = "attachment-1"
	return &a, nil
}

type uploadFixture struct {
	handler *UploadHandler
	objects *fakeObjects
	records *fakeRecords
	signer  *auth.Signer
}

func newUploadFixture(t *testing.T) uploadFixture {
	t.Helper()
	signer, err := auth.NewSigner("test-auth-secret-that-is-long-enough", time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	objects := &fakeObjects{}
	records := &fakeRecords{record: &servicerecord.ServiceRecord{ID: uploadRecordID, WorkshopID: uploadWorkshop}}
	logger := slog.New(slog.NewTextHandler(io.Discard, nil))
	return uploadFixture{
		handler: NewUploadHandler(objects, records, signer, logger),
		objects: objects,
		records: records,
		signer:  signer,
	}
}

func (f uploadFixture) token(t *testing.T, kind auth.Kind, id string) string {
	t.Helper()
	token, err := f.signer.Issue(auth.Subject{Kind: kind, ID: id}, time.Now())
	if err != nil {
		t.Fatal(err)
	}
	return token
}

func multipartBody(t *testing.T, declaredType string, content []byte, fields map[string]string) (*bytes.Buffer, string) {
	t.Helper()
	var body bytes.Buffer
	writer := multipart.NewWriter(&body)
	for name, value := range fields {
		if err := writer.WriteField(name, value); err != nil {
			t.Fatal(err)
		}
	}
	header := textproto.MIMEHeader{}
	header.Set("Content-Disposition", `form-data; name="file"; filename="photo.png"`)
	header.Set("Content-Type", declaredType)
	part, err := writer.CreatePart(header)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := part.Write(content); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	return &body, writer.FormDataContentType()
}

func (f uploadFixture) serve(t *testing.T, token string, body io.Reader, contentType string) *httptest.ResponseRecorder {
	t.Helper()
	mux := http.NewServeMux()
	mux.Handle("POST /v1/service-records/{id}/attachments", f.handler)

	req := httptest.NewRequest(http.MethodPost, "/v1/service-records/"+uploadRecordID+"/attachments", body)
	req.Header.Set("Content-Type", contentType)
	if token != "" {
		req.Header.Set("Authorization", "Bearer "+token)
	}
	rec := httptest.NewRecorder()
	mux.ServeHTTP(rec, req)
	return rec
}

func TestUploadStoresAPhoto(t *testing.T) {
	f := newUploadFixture(t)
	body, contentType := multipartBody(t, "image/png", onePixelPNG, map[string]string{"phase": "after"})

	rec := f.serve(t, f.token(t, auth.KindWorkshop, uploadWorkshop), body, contentType)

	if rec.Code != http.StatusOK {
		t.Fatalf("status = %d, body %s", rec.Code, rec.Body)
	}
	if !bytes.Contains(rec.Body.Bytes(), []byte(`"phase":"PHOTO_PHASE_AFTER"`)) {
		t.Errorf("response %s lacks the wire phase", rec.Body)
	}
}

func TestUploadRefusals(t *testing.T) {
	t.Run("owner token", func(t *testing.T) {
		f := newUploadFixture(t)
		body, contentType := multipartBody(t, "image/png", onePixelPNG, nil)
		rec := f.serve(t, f.token(t, auth.KindOwner, "owner-1"), body, contentType)
		assertStatus(t, rec, http.StatusUnauthorized)
	})

	t.Run("another workshop's record is refused before storing", func(t *testing.T) {
		f := newUploadFixture(t)
		body, contentType := multipartBody(t, "image/png", onePixelPNG, nil)
		rec := f.serve(t, f.token(t, auth.KindWorkshop, "someone-else"), body, contentType)
		assertStatus(t, rec, http.StatusNotFound)
		if f.objects.putType != "" {
			t.Error("a file was stored for a record the caller does not own")
		}
	})

	t.Run("html declared as png", func(t *testing.T) {
		f := newUploadFixture(t)
		body, contentType := multipartBody(t, "image/png", []byte("<html><script>alert(1)</script></html>"), nil)
		rec := f.serve(t, f.token(t, auth.KindWorkshop, uploadWorkshop), body, contentType)
		assertStatus(t, rec, http.StatusBadRequest)
	})

	t.Run("not multipart", func(t *testing.T) {
		f := newUploadFixture(t)
		rec := f.serve(t, f.token(t, auth.KindWorkshop, uploadWorkshop), bytes.NewBufferString("{}"), "application/json")
		assertStatus(t, rec, http.StatusBadRequest)
	})

	t.Run("phase on an invoice", func(t *testing.T) {
		f := newUploadFixture(t)
		body, contentType := multipartBody(t, "image/png", onePixelPNG, map[string]string{"kind": "invoice", "phase": "before"})
		rec := f.serve(t, f.token(t, auth.KindWorkshop, uploadWorkshop), body, contentType)
		assertStatus(t, rec, http.StatusBadRequest)
	})
}

func TestUploadRemovesTheFileWhenLinkingFails(t *testing.T) {
	f := newUploadFixture(t)
	f.records.attachErr = errors.New("database down")
	body, contentType := multipartBody(t, "image/png", onePixelPNG, nil)

	rec := f.serve(t, f.token(t, auth.KindWorkshop, uploadWorkshop), body, contentType)

	assertStatus(t, rec, http.StatusInternalServerError)
	if len(f.objects.deleted) != 1 {
		t.Errorf("deleted = %v, want the orphaned file removed", f.objects.deleted)
	}
}

func assertStatus(t *testing.T, rec *httptest.ResponseRecorder, want int) {
	t.Helper()
	if rec.Code != want {
		t.Fatalf("status = %d, want %d (body %s)", rec.Code, want, rec.Body)
	}
}
