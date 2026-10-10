package server

import (
	"context"
	"errors"
	"log/slog"
	"time"

	"connectrpc.com/connect"
)

// LoggingInterceptor logs procedure, duration and status of every unary RPC.
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
				code := codeOf(err)
				logger.Log(ctx, levelFor(code), "rpc failed", append(attrs, "code", code, "err", err)...)
			} else {
				logger.InfoContext(ctx, "rpc handled", attrs...)
			}

			return res, err
		}
	})
}

// levelFor keeps a wrong password or an unknown plate out of the error log,
// which should only hold failures someone needs to act on.
func levelFor(code connect.Code) slog.Level {
	switch code {
	case connect.CodeInvalidArgument, connect.CodeNotFound, connect.CodeAlreadyExists,
		connect.CodeUnauthenticated, connect.CodePermissionDenied,
		connect.CodeFailedPrecondition, connect.CodeResourceExhausted:
		return slog.LevelWarn
	default:
		return slog.LevelError
	}
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
