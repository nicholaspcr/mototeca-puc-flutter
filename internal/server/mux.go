// Package server wires up the HTTP mux and cross-cutting middleware for the
// Mototeca API, kept separate from cmd/api/main.go so main stays a thin
// composition root.
package server

import (
	"fmt"
	"log/slog"
	"net/http"

	"connectrpc.com/connect"
	"connectrpc.com/otelconnect"

	"mototeca-backend/internal/gen/mototeca/vehicle/v1/vehiclev1connect"
)

// NewMux builds the HTTP mux serving the Connect-RPC API and health check.
// Every RPC is wrapped with tracing (outermost, so the span covers the full
// request) and then request logging.
func NewMux(vehicleHandler vehiclev1connect.VehicleServiceHandler, logger *slog.Logger) (*http.ServeMux, error) {
	otelInterceptor, err := otelconnect.NewInterceptor()
	if err != nil {
		return nil, fmt.Errorf("creating otel interceptor: %w", err)
	}

	mux := http.NewServeMux()

	vehiclePath, vehicleConnectHandler := vehiclev1connect.NewVehicleServiceHandler(
		vehicleHandler,
		connect.WithInterceptors(otelInterceptor, LoggingInterceptor(logger)),
	)
	mux.Handle(vehiclePath, vehicleConnectHandler)

	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
	})

	return mux, nil
}
