// Package storage puts service photos in S3-compatible object storage, kept
// out of Postgres so the database stays small and the files stream directly.
package storage

import (
	"context"
	"errors"
	"fmt"
	"io"
	"net/url"
	"path"
	"strings"

	"github.com/google/uuid"
	"github.com/minio/minio-go/v7"
	"github.com/minio/minio-go/v7/pkg/credentials"
)

// MaxPhotoBytes caps one upload. Phone photos land well under this; the limit
// exists so a single request cannot exhaust the API's memory.
const MaxPhotoBytes = 8 << 20 // 8 MiB

// allowedTypes is an allowlist: anything not named here is rejected rather
// than stored and served back to other users.
var allowedTypes = map[string]string{
	"image/jpeg":      ".jpg",
	"image/png":       ".png",
	"image/webp":      ".webp",
	"application/pdf": ".pdf",
}

var ErrUnsupportedType = errors.New("unsupported file type")

type Config struct {
	Endpoint  string
	AccessKey string
	SecretKey string
	Bucket    string
	// PublicURL is how a client reaches the bucket, which differs from
	// Endpoint whenever the API talks to storage over an internal network.
	PublicURL string
	UseSSL    bool
}

type Store struct {
	client    *minio.Client
	bucket    string
	publicURL string
}

// New connects and creates the bucket when it is missing, so a fresh
// environment needs no manual setup step.
func New(ctx context.Context, cfg Config) (*Store, error) {
	client, err := minio.New(cfg.Endpoint, &minio.Options{
		Creds:  credentials.NewStaticV4(cfg.AccessKey, cfg.SecretKey, ""),
		Secure: cfg.UseSSL,
	})
	if err != nil {
		return nil, fmt.Errorf("connecting to object storage: %w", err)
	}

	exists, err := client.BucketExists(ctx, cfg.Bucket)
	if err != nil {
		return nil, fmt.Errorf("checking bucket %q: %w", cfg.Bucket, err)
	}
	if !exists {
		if err := client.MakeBucket(ctx, cfg.Bucket, minio.MakeBucketOptions{}); err != nil {
			return nil, fmt.Errorf("creating bucket %q: %w", cfg.Bucket, err)
		}
	}

	if err := client.SetBucketPolicy(ctx, cfg.Bucket, readOnlyPolicy(cfg.Bucket)); err != nil {
		return nil, fmt.Errorf("setting bucket policy on %q: %w", cfg.Bucket, err)
	}

	return &Store{
		client:    client,
		bucket:    cfg.Bucket,
		publicURL: strings.TrimRight(cfg.PublicURL, "/"),
	}, nil
}

// readOnlyPolicy allows anonymous GET on the bucket's objects.
//
// The plate lookup is public by design, so the photos hanging off it have to
// be readable without an account. Object names are random UUIDs, so a URL
// cannot be guessed from a plate — but this is obscurity, not authorization.
// Presigned, expiring URLs are the hardening step if photos ever carry
// anything more sensitive than a picture of a chain.
func readOnlyPolicy(bucket string) string {
	return `{
	  "Version": "2012-10-17",
	  "Statement": [{
	    "Effect": "Allow",
	    "Principal": {"AWS": ["*"]},
	    "Action": ["s3:GetObject"],
	    "Resource": ["arn:aws:s3:::` + bucket + `/*"]
	  }]
	}`
}

// Put stores one file under a generated name and returns its URL. The name is
// never taken from the client, so an upload cannot overwrite another's file or
// smuggle a path.
func (s *Store) Put(ctx context.Context, prefix, contentType string, size int64, body io.Reader) (string, error) {
	extension, ok := allowedTypes[contentType]
	if !ok {
		return "", ErrUnsupportedType
	}
	if size <= 0 || size > MaxPhotoBytes {
		return "", fmt.Errorf("file must be between 1 byte and %d MiB", MaxPhotoBytes>>20)
	}

	object := path.Join(prefix, uuid.NewString()+extension)
	if _, err := s.client.PutObject(ctx, s.bucket, object, body, size,
		minio.PutObjectOptions{ContentType: contentType}); err != nil {
		return "", fmt.Errorf("storing %q: %w", object, err)
	}

	return s.publicURL + "/" + s.bucket + "/" + object, nil
}

// SupportedTypes lists the accepted content types, for error messages.
func SupportedTypes() []string {
	types := make([]string, 0, len(allowedTypes))
	for t := range allowedTypes {
		types = append(types, t)
	}
	return types
}

// ObjectName extracts the stored object from a URL this Store produced.
func (s *Store) ObjectName(rawURL string) (string, bool) {
	parsed, err := url.Parse(rawURL)
	if err != nil {
		return "", false
	}
	prefix := "/" + s.bucket + "/"
	if !strings.HasPrefix(parsed.Path, prefix) {
		return "", false
	}
	return strings.TrimPrefix(parsed.Path, prefix), true
}
