// Package server wires the HTTP mux and middleware of the Mototeca API.
package server

import (
	"context"
	"fmt"
	"log/slog"
	"net/http"
	"time"

	"connectrpc.com/connect"
	"connectrpc.com/otelconnect"

	"mototeca-backend/internal/auth"
	"mototeca-backend/internal/gen/mototeca/owner/v1/ownerv1connect"
	"mototeca-backend/internal/gen/mototeca/service/v1/servicev1connect"
	"mototeca-backend/internal/gen/mototeca/vehicle/v1/vehiclev1connect"
	"mototeca-backend/internal/gen/mototeca/workshop/v1/workshopv1connect"
)

// Pinger is the health check's view of the database.
type Pinger interface {
	Ping(ctx context.Context) error
}

const maxRPCBytes = 1 << 20

// Handlers are the per-domain Connect implementations the mux serves.
type Handlers struct {
	Vehicle       vehiclev1connect.VehicleServiceHandler
	Workshop      workshopv1connect.WorkshopServiceHandler
	ServiceRecord servicev1connect.ServiceRecordServiceHandler
	Owner         ownerv1connect.OwnerServiceHandler
}

// rateLimits are stricter limits for logins and the public plate lookup.
func rateLimits() map[string]*RateLimiter {
	return map[string]*RateLimiter{
		workshopv1connect.WorkshopServiceLoginProcedure:                         NewRateLimiter(0.2, 5),
		workshopv1connect.WorkshopServiceCreateWorkshopProcedure:                NewRateLimiter(0.05, 3),
		servicev1connect.ServiceRecordServiceListServiceRecordsByPlateProcedure: NewRateLimiter(1, 20),
		ownerv1connect.OwnerServiceLoginProcedure:                               NewRateLimiter(0.2, 5),
		ownerv1connect.OwnerServiceCreateOwnerProcedure:                         NewRateLimiter(0.05, 3),
		// Each attempt is a guess at a chassi suffix.
		ownerv1connect.OwnerServiceClaimVehicleProcedure: NewRateLimiter(0.1, 10),
	}
}

// NewMux builds the API mux. Interceptors run tracing, rate limit, logging,
// then auth. The upload route exists only when uploads is non-nil.
func NewMux(handlers Handlers, uploads *UploadHandler, signer *auth.Signer, db Pinger, logger *slog.Logger) (*http.ServeMux, error) {
	otelInterceptor, err := otelconnect.NewInterceptor()
	if err != nil {
		return nil, fmt.Errorf("creating otel interceptor: %w", err)
	}

	interceptors := connect.WithHandlerOptions(
		connect.WithInterceptors(
			otelInterceptor,
			RateLimitInterceptor(rateLimits(), NewRateLimiter(10, 40)),
			LoggingInterceptor(logger),
			auth.Interceptor(signer),
		),
		// No RPC carries files, so a body this large is abuse, not data.
		connect.WithReadMaxBytes(maxRPCBytes),
	)

	mux := http.NewServeMux()

	for _, register := range []func() (string, http.Handler){
		func() (string, http.Handler) {
			return vehiclev1connect.NewVehicleServiceHandler(handlers.Vehicle, interceptors)
		},
		func() (string, http.Handler) {
			return workshopv1connect.NewWorkshopServiceHandler(handlers.Workshop, interceptors)
		},
		func() (string, http.Handler) {
			return servicev1connect.NewServiceRecordServiceHandler(handlers.ServiceRecord, interceptors)
		},
		func() (string, http.Handler) {
			return ownerv1connect.NewOwnerServiceHandler(handlers.Owner, interceptors)
		},
	} {
		path, handler := register()
		mux.Handle(path, handler)
	}

	if uploads != nil {
		mux.Handle("POST /v1/service-records/{id}/attachments", RateLimitHTTP(NewRateLimiter(1, 10), uploads))
	}

	// Reports the database too: an instance that can't reach Postgres serves
	// nothing useful, and a 200 would keep a load balancer routing to it.
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, r *http.Request) {
		ctx, cancel := context.WithTimeout(r.Context(), 2*time.Second)
		defer cancel()

		if err := db.Ping(ctx); err != nil {
			logger.ErrorContext(ctx, "health check failed", "err", err)
			http.Error(w, "database unavailable", http.StatusServiceUnavailable)
			return
		}
		w.WriteHeader(http.StatusOK)
	})

	return mux, nil
}
