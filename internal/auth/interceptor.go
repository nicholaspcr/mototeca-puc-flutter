package auth

import (
	"context"
	"errors"
	"strings"
	"time"

	"connectrpc.com/connect"
)

type contextKey struct{}

var subjectKey contextKey

// Interceptor authenticates but does not authorize: it reads a bearer token
// when one is present and annotates the context with the subject it belongs
// to. Requests without a token pass through untouched, because the plate
// lookup and service detail are deliberately public.
//
// Enforcement is the handler's job, via RequireWorkshopID / RequireOwnerID.
func Interceptor(signer *Signer) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			token, ok := bearerToken(req.Header().Get("Authorization"))
			if !ok {
				return next(ctx, req)
			}

			subject, err := signer.Verify(token, time.Now())
			if err != nil {
				// A bad token is an error, not an anonymous request: otherwise
				// an expired session degrades into a confusing "not found".
				return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("invalid or expired session"))
			}

			return next(WithSubject(ctx, subject), req)
		}
	}
}

func bearerToken(header string) (string, bool) {
	scheme, token, found := strings.Cut(header, " ")
	if !found || !strings.EqualFold(scheme, "Bearer") {
		return "", false
	}
	token = strings.TrimSpace(token)
	return token, token != ""
}

// WithSubject returns ctx carrying an authenticated subject.
func WithSubject(ctx context.Context, subject Subject) context.Context {
	return context.WithValue(ctx, subjectKey, subject)
}

// WithWorkshopID is shorthand for a workshop session, used by tests.
func WithWorkshopID(ctx context.Context, id string) context.Context {
	return WithSubject(ctx, Subject{Kind: KindWorkshop, ID: id})
}

// WithOwnerID is shorthand for an owner session, used by tests.
func WithOwnerID(ctx context.Context, id string) context.Context {
	return WithSubject(ctx, Subject{Kind: KindOwner, ID: id})
}

// SubjectFrom returns the authenticated subject, if any.
func SubjectFrom(ctx context.Context) (Subject, bool) {
	subject, ok := ctx.Value(subjectKey).(Subject)
	return subject, ok && subject.ID != ""
}

// require rejects the wrong kind of token exactly like no token at all.
func require(ctx context.Context, want Kind, message string) (string, error) {
	subject, ok := SubjectFrom(ctx)
	if !ok || subject.Kind != want {
		return "", connect.NewError(connect.CodeUnauthenticated, errors.New(message))
	}
	return subject.ID, nil
}

// RequireSubject accepts a session of either kind.
func RequireSubject(ctx context.Context) (Subject, error) {
	subject, ok := SubjectFrom(ctx)
	if !ok {
		return Subject{}, connect.NewError(connect.CodeUnauthenticated, errors.New("authentication required"))
	}
	return subject, nil
}

// RequireWorkshopID returns the authenticated workshop id, or a Connect
// UNAUTHENTICATED error suitable for returning straight to the client.
func RequireWorkshopID(ctx context.Context) (string, error) {
	return require(ctx, KindWorkshop, "workshop authentication required")
}

// RequireOwnerID returns the authenticated owner id, or a Connect
// UNAUTHENTICATED error.
func RequireOwnerID(ctx context.Context) (string, error) {
	return require(ctx, KindOwner, "owner authentication required")
}
