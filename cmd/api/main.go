package main

import (
	"context"
	"log"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"mototeca-backend/internal/auth"
	"mototeca-backend/internal/config"
	"mototeca-backend/internal/db"
	"mototeca-backend/internal/logging"
	"mototeca-backend/internal/owner"
	"mototeca-backend/internal/server"
	"mototeca-backend/internal/servicerecord"
	"mototeca-backend/internal/telemetry"
	"mototeca-backend/internal/vehicle"
	"mototeca-backend/internal/workshop"
)

func main() {
	// Config isn't loaded yet, so bootstrap failures use the stdlib logger.
	cfg, err := config.Load()
	if err != nil {
		log.Fatalf("loading config: %v", err)
	}

	logger := logging.New(cfg.LogFormat)
	slog.SetDefault(logger)

	shutdownTracing, err := telemetry.Setup(context.Background(), cfg.OTelExporter, cfg.OTelEndpoint)
	if err != nil {
		logger.Error("setting up tracing", "err", err)
		os.Exit(1)
	}
	defer func() {
		ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancel()
		if err := shutdownTracing(ctx); err != nil {
			logger.Error("shutting down tracing", "err", err)
		}
	}()

	pool, err := db.NewPool(context.Background(), cfg.DatabaseURL)
	if err != nil {
		logger.Error("connecting to database", "err", err)
		os.Exit(1)
	}
	defer pool.Close()

	signer, err := auth.NewSigner(cfg.AuthSecret, cfg.AuthTokenTTL)
	if err != nil {
		logger.Error("configuring auth", "err", err)
		os.Exit(1)
	}

	// One service-record repository, shared: the owner domain reads through it
	// to show the last service on each bike.
	serviceRecords := servicerecord.NewRepository(pool)

	handlers := server.Handlers{
		Vehicle:       vehicle.NewHandler(vehicle.NewRepository(pool), logger),
		Workshop:      workshop.NewHandler(workshop.NewRepository(pool), signer, logger),
		ServiceRecord: servicerecord.NewHandler(serviceRecords, logger),
		Owner:         owner.NewHandler(owner.NewRepository(pool), serviceRecords, signer, logger),
	}

	mux, err := server.NewMux(handlers, signer, pool, logger)
	if err != nil {
		logger.Error("building http mux", "err", err)
		os.Exit(1)
	}

	httpServer := &http.Server{
		Addr:         ":" + cfg.Port,
		Handler:      mux,
		ReadTimeout:  5 * time.Second,
		WriteTimeout: 10 * time.Second,
	}

	go func() {
		logger.Info("mototeca api listening", "port", cfg.Port)
		if err := httpServer.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.Error("server error", "err", err)
			os.Exit(1)
		}
	}()

	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGINT, syscall.SIGTERM)
	<-stop

	ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
	defer cancel()
	_ = httpServer.Shutdown(ctx)
}
