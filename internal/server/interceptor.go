package server

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"connectrpc.com/connect"
)

// LoggingInterceptor logs the procedure, duration, and resulting status code
// for every unary RPC — one place to log requests instead of each handler
// doing it ad hoc.
func LoggingInterceptor(logger *slog.Logger) connect.Interceptor {
	return connect.UnaryInterceptorFunc(func(next connect.UnaryFunc) connect.UnaryFunc {
		return func(ctx context.Context, req connect.AnyRequest) (connect.AnyResponse, error) {
			start := time.Now()
			res, err := next(ctx, req)
			duration := time.Since(start)

			attrs := []any{
				"method", req.Spec().Procedure,
				"duration_ms", duration.Milliseconds(),
			}
			if err != nil {
				logger.ErrorContext(ctx, "rpc failed", append(attrs, "code", codeOf(err), "err", err)...)
			} else {
				logger.InfoContext(ctx, "rpc handled", attrs...)
			}

			return res, err
		}
	})
}

// codeOf extracts the Connect status code from err, falling back to
// CodeUnknown for errors that didn't originate from connect.NewError.
func codeOf(err error) connect.Code {
	var connectErr *connect.Error
	if errors.As(err, &connectErr) {
		return connectErr.Code()
	}
	return connect.CodeUnknown
}
