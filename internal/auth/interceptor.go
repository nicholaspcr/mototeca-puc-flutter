package auth

import (
	"context"
	"errors"
	"strings"
	"time"

	"connectrpc.com/connect"
)

type contextKey struct{}

var workshopIDKey contextKey

// Interceptor authenticates but does not authorize: it reads a bearer token
// when one is present and annotates the context with the workshop it belongs
// to. Requests without a token pass through untouched, because the plate
// lookup and service detail are deliberately public.
//
// Enforcement is the handler's job, via RequireWorkshopID.
func Interceptor(signer *Signer) connect.UnaryInterceptorFunc {
	return func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			token, ok := bearerToken(req.Header().Get("Authorization"))
			if !ok {
				return next(ctx, req)
			}

			workshopID, err := signer.Verify(token, time.Now())
			if err != nil {
				// A token that was sent but is bad is an error, not an
				// anonymous request — otherwise an expired session silently
				// degrades into a confusing "not found".
				return nil, connect.NewError(connect.CodeUnauthenticated, errors.New("invalid or expired session"))
			}

			return next(WithWorkshopID(ctx, workshopID), req)
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

// WithWorkshopID returns ctx carrying an authenticated workshop id.
func WithWorkshopID(ctx context.Context, workshopID string) context.Context {
	return context.WithValue(ctx, workshopIDKey, workshopID)
}

// WorkshopID returns the authenticated workshop id, if any.
func WorkshopID(ctx context.Context) (string, bool) {
	id, ok := ctx.Value(workshopIDKey).(string)
	return id, ok && id != ""
}

// RequireWorkshopID returns the authenticated workshop id, or a Connect
// UNAUTHENTICATED error suitable for returning straight to the client.
func RequireWorkshopID(ctx context.Context) (string, error) {
	id, ok := WorkshopID(ctx)
	if !ok {
		return "", connect.NewError(connect.CodeUnauthenticated, errors.New("workshop authentication required"))
	}
	return id, nil
}
