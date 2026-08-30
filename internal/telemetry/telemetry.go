// Package telemetry configures OpenTelemetry tracing for the API.
package telemetry

import (
	"context"
	"fmt"

	"go.opentelemetry.io/otel"
	"go.opentelemetry.io/otel/attribute"
	"go.opentelemetry.io/otel/exporters/otlp/otlptrace/otlptracehttp"
	"go.opentelemetry.io/otel/exporters/stdout/stdouttrace"
	"go.opentelemetry.io/otel/sdk/resource"
	sdktrace "go.opentelemetry.io/otel/sdk/trace"
)

const serviceName = "mototeca-api"

// Shutdown flushes and closes the trace provider. Callers should invoke it
// on graceful shutdown, e.g. via defer.
type Shutdown func(context.Context) error

var noopShutdown Shutdown = func(context.Context) error { return nil }

// Setup installs the global TracerProvider for the given exporter ("none",
// "stdout", or "otlp") and returns a Shutdown func. "none" is the default:
// it installs nothing, so tracing has zero runtime cost and nobody needs a
// collector running just to `make run`.
func Setup(ctx context.Context, exporter, otlpEndpoint string) (Shutdown, error) {
	if exporter == "" || exporter == "none" {
		return noopShutdown, nil
	}

	spanExporter, err := newExporter(ctx, exporter, otlpEndpoint)
	if err != nil {
		return nil, fmt.Errorf("creating %s span exporter: %w", exporter, err)
	}

	res, err := resource.New(ctx, resource.WithAttributes(
		attribute.String("service.name", serviceName),
	))
	if err != nil {
		return nil, fmt.Errorf("building otel resource: %w", err)
	}

	tp := sdktrace.NewTracerProvider(
		sdktrace.WithBatcher(spanExporter),
		sdktrace.WithResource(res),
	)
	otel.SetTracerProvider(tp)

	return tp.Shutdown, nil
}

func newExporter(ctx context.Context, exporter, otlpEndpoint string) (sdktrace.SpanExporter, error) {
	switch exporter {
	case "stdout":
		return stdouttrace.New(stdouttrace.WithPrettyPrint())
	case "otlp":
		var opts []otlptracehttp.Option
		if otlpEndpoint != "" {
			opts = append(opts, otlptracehttp.WithEndpoint(otlpEndpoint))
		}
		return otlptracehttp.New(ctx, opts...)
	default:
		return nil, fmt.Errorf("unknown exporter %q (want none, stdout, or otlp)", exporter)
	}
}
