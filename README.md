# Mototeca

Service/repair history for motorcycles in Brazil — mechanics log work, owners
look up a bike's full history by plate. See [ARCHITECTURE.md](ARCHITECTURE.md)
for the product/domain context, data model, and infra rationale. This file is
the "get running" doc.

This repo currently holds the **backend API**. The mobile client is a
**Flutter app** (the discipline this project is built for requires Flutter,
not a web frontend) — it isn't implemented yet; `design/` has the screen
mockups/brand reference it should be built from.

## Stack

| | |
|---|---|
| Backend | Go, [Connect-RPC](https://connectrpc.com) over HTTP, Postgres ([pgx](https://github.com/jackc/pgx)) |
| Mobile client | Flutter — planned, not yet in this repo (see `design/`) |
| API contract | Protobuf (`proto/`) → generated Go server code via [buf](https://buf.build) |
| Observability | `log/slog` structured logs, OpenTelemetry tracing (RPC spans → pgx query spans) |

The Go API is a normal Go module at the repo root. It has no bundled client:
Connect-RPC serves both the gRPC-Web protocol and plain HTTP+JSON (the
"Connect" protocol), so the Flutter app can call it with a regular HTTP
client and JSON request/response bodies — no generated Dart stubs required
to get started.

## Calling the API (Flutter side)

Every RPC is a `POST` to `/<package>.<Service>/<Method>` with
`Content-Type: application/json`. No gRPC/Connect client library needed —
`package:http` + `dart:convert` is enough.

```bash
curl -s http://localhost:8080/mototeca.vehicle.v1.VehicleService/CreateVehicle \
  -H "Content-Type: application/json" \
  -d '{"plate":"ABC1D23","chassi":"9BWZZZ377VT004251","make":"Honda","model":"CG 160","year":2022}'
# -> {"vehicle":{"id":"...","plate":"ABC1D23","chassi":"9BWZZZ377VT004251","make":"Honda","model":"CG 160","year":2022,"createdAt":"2026-08-30T12:00:00Z"}}

curl -s http://localhost:8080/mototeca.vehicle.v1.VehicleService/GetVehicleByPlate \
  -H "Content-Type: application/json" \
  -d '{"plate":"ABC1D23"}'
```

Two things to know when mirroring these shapes in Dart models:
- Protobuf JSON uses **camelCase** field names, not the `snake_case` seen in
  `.proto` (`current_owner_id` → `currentOwnerId`, `created_at` →
  `createdAt`).
- Errors come back as a plain JSON body — `{"code":"invalid_argument","message":"..."}`
  — with a matching non-2xx HTTP status. No envelope/wrapper to unwrap.

## Prerequisites

- Go 1.26+
- Docker (for local Postgres)
- [buf](https://buf.build/docs/installation) — only needed if you change `proto/*.proto`

## Quickstart

```bash
# 1. Database
cp .env.example .env        # defaults already match docker-compose.yml
make db-up                   # starts Postgres, waits until ready
make migrate                 # applies db/migrations/0001_init.sql

# 2. Backend — starts API on :8080
make run
```

## Repo layout

```
cmd/api/            main.go — composition root (config → logging → tracing → db → handlers → http.Server)
internal/
  config/            typed env config (Load() validates + defaults)
  logging/            slog setup (text/json)
  telemetry/           OpenTelemetry SDK setup (none/stdout/otlp exporters)
  db/                 pgx pool setup (with otelpgx tracer attached)
  server/               http.ServeMux wiring, Connect interceptors (logging, otel)
  vehicle/            the one existing domain vertical slice (see below)
  gen/                 generated Go protobuf/Connect code — do not edit
proto/mototeca/…/*.proto   API contracts, source of truth for gen/
db/migrations/       plain SQL migrations, applied in order
design/              reference bundle for brand/UI design tokens + screen mockups — not app code, input for the Flutter client
```

### The `vehicle` vertical slice

`internal/vehicle` is the template for adding the next domain (service
records, workshops, owners). Each domain package owns:

```
types.go       domain structs
validate.go    input validation, independent of transport/storage
repository.go  Postgres access (implements Store)
store.go       Store interface — lets Handler depend on an interface, not *Repository
handler.go     Connect-RPC handler — wraps/logs repo errors, returns opaque connect.Code* to clients
*_test.go      unit tests against a fake Store (no DB needed)
repository_integration_test.go   //go:build integration — real Postgres, run via make test-integration
```

No client consumes it yet — the Flutter app (not started) will call
`POST /mototeca.vehicle.v1.VehicleService/<Method>` with a JSON body once it
exists.

## Common commands

```bash
make help              # list all backend targets

make run                # go run ./cmd/api
make build              # static binary → bin/api
make test                # unit tests, no DB (./cmd/... ./internal/...)
make test-integration    # + DB-backed tests (needs `make db-up` first)
make generate             # buf generate — regenerate Go code from proto/

make db-up / db-down / db-logs   # local Postgres container
make migrate                      # apply db/migrations/0001_init.sql
```

## Configuration

Backend env vars (`.env`, see `.env.example`):

| Var | Default | Notes |
|---|---|---|
| `DATABASE_URL` | — | required |
| `PORT` | `8080` | |
| `LOG_FORMAT` | `text` | `text` or `json` |
| `OTEL_EXPORTER` | `none` | `none`, `stdout`, or `otlp` |
| `OTEL_EXPORTER_OTLP_ENDPOINT` | — | required if `OTEL_EXPORTER=otlp` |

## Conventions

- **Errors**: wrap with context (`fmt.Errorf("doing x: %w", err)`), log the
  wrapped error server-side, return an opaque `connect.CodeInternal` (etc.)
  to the client — never leak internal error strings over the wire.
- **Storage decoupling**: handlers depend on a `Store` interface, not a
  concrete repository, so unit tests use an in-memory fake and don't need a
  database. DB-touching tests are tagged `integration` and excluded from
  `make test`.
- **Tracing**: context propagates automatically from the Connect interceptor
  through to pgx — don't thread spans manually, just pass `ctx` through.
- **Commits**: small, single-purpose, one-line message (imperative mood).
- **`internal/gen`**: generated from `proto/`, never hand-edited — run
  `make generate` after changing a `.proto` file.
