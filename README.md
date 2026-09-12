# Mototeca

Service/repair history for motorcycles in Brazil — mechanics log work, owners
look up a bike's full history by plate. See [ARCHITECTURE.md](ARCHITECTURE.md)
for the product/domain context, data model, and infra rationale. This file is
the "get running" doc.

This repo holds the **Go backend API** (repo root) and the **Flutter app**
(`mobile/`). The oficina flow and the public plate lookup run against the real
API; the proprietário screens (Minhas Motos, Lembretes) still render sample
data, because owner sign-in is phone+OTP and there is no SMS/WhatsApp sender
yet. `design/` holds the screen mockups the UI was built from.

## Stack

| | |
|---|---|
| Backend | Go, [Connect-RPC](https://connectrpc.com) over HTTP, Postgres ([pgx](https://github.com/jackc/pgx)) |
| Mobile client | Flutter (`mobile/`) — `package:http` + `dart:convert`, no generated Dart stubs |
| API contract | Protobuf (`proto/`) → generated Go server code via [buf](https://buf.build) |
| Observability | `log/slog` structured logs, OpenTelemetry tracing (RPC spans → pgx query spans) |

The Go API is a normal Go module at the repo root. Connect-RPC serves both the
gRPC-Web protocol and plain HTTP+JSON (the "Connect" protocol), so the Flutter
app calls it with a regular HTTP client and JSON bodies — no generated Dart
stubs (ARCHITECTURE.md section 5).

## Endpoints

| Procedure | Auth | Used by |
|---|---|---|
| `workshop.v1.WorkshopService/CreateWorkshop` | public | Cadastrar Oficina |
| `workshop.v1.WorkshopService/Login` | public | Login (oficina) |
| `vehicle.v1.VehicleService/CreateVehicle` | public | Cadastrar Veículo |
| `vehicle.v1.VehicleService/GetVehicleByPlate` | public | Novo Registro (busca) |
| `service.v1.ServiceRecordService/CreateServiceRecord` | **workshop token** | Novo Registro (salvar) |
| `service.v1.ServiceRecordService/ListWorkshopServiceRecords` | **workshop token** | Painel da Oficina |
| `service.v1.ServiceRecordService/ListServiceRecordsByPlate` | public | Portal do Proprietário |
| `service.v1.ServiceRecordService/GetServiceRecord` | public | Detalhe do Serviço |

All procedure names are prefixed with `mototeca.` — e.g.
`POST /mototeca.workshop.v1.WorkshopService/Login`.

### Auth

`Login` and `CreateWorkshop` return a `token`; send it back as
`Authorization: Bearer <token>`. It is an HMAC-signed string carrying the
workshop id and an expiry (12h), so verifying costs no database round-trip —
the trade-off is that it cannot be revoked before it expires. Passwords are
stored as bcrypt digests. A workshop can only ever write records under its own
name: the handler takes the workshop id from the token, never from the request
body.

`Login` returns the same `unauthenticated` error for an unknown CNPJ and a
wrong password, so it can't be used to discover which shops are registered.
`Login`, `CreateWorkshop` and the public plate lookup are rate-limited per
caller address (in-process — a multi-instance deployment needs a shared
store).

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
make migrate                 # applies every db/migrations/*.sql in order

# 2. Backend — starts API on :8080
export AUTH_SECRET="$(openssl rand -base64 48)"   # or set it in .env
make run

# 3. Flutter app (separate terminal)
cd mobile && flutter run -d chrome
```

Everything in one place instead, API included:

```bash
docker compose up -d          # db + api
make e2e                       # smoke-tests every endpoint against it
```

See [mobile/DEMO.md](mobile/DEMO.md) for running the app in class.

## Repo layout

```
cmd/api/            main.go — composition root (config → logging → tracing → db → handlers → http.Server)
internal/
  config/            typed env config (Load() validates + defaults)
  logging/            slog setup (text/json)
  telemetry/           OpenTelemetry SDK setup (none/stdout/otlp exporters)
  db/                 pgx pool setup (with otelpgx tracer attached)
  server/               http.ServeMux wiring, Connect interceptors (logging, otel, rate limit)
  auth/                bcrypt passwords, HMAC session tokens, auth interceptor
  vehicle/             domain vertical slice — the template (see below)
  workshop/            signup + login
  servicerecord/       the core: records, operations, parts
  gen/                 generated Go protobuf/Connect code — do not edit
proto/mototeca/…/*.proto   API contracts, source of truth for gen/
db/migrations/       plain SQL migrations, applied in order
scripts/e2e.sh       end-to-end smoke test of every endpoint (see `make e2e`)
mobile/              the Flutter app
design/              screen mockups + brand tokens — not app code, the reference the UI was built from
```

### The Flutter app

```
lib/api/           ApiClient (Connect-over-JSON) + typed ApiException
lib/models/        Dart mirrors of the proto messages, hand-written
lib/repositories/  one per service — where procedure names live
lib/state/         AppScope/AppState — the session and the repositories
lib/screens/       one file per screen, matching design/NAVIGATION.md
lib/data/          sample data, proprietário side only
test/fixtures/     JSON captured from the real API, used by contract_test.dart
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

`internal/workshop` and `internal/servicerecord` follow the same shape.

## Common commands

```bash
make help              # list all backend targets

make run                # go run ./cmd/api
make build              # static binary → bin/api
make test                # unit tests, no DB (./cmd/... ./internal/...)
make test-integration    # + DB-backed tests (needs `make db-up` first)
make generate             # buf generate — regenerate Go code from proto/

make db-up / db-down / db-logs   # local Postgres container
make migrate                      # apply every db/migrations/*.sql
make e2e                           # end-to-end smoke test (needs `docker compose up -d api`)

cd mobile && flutter test          # 36 tests: API client, contract, navigation
cd mobile && flutter analyze
```

## Configuration

Backend env vars (`.env`, see `.env.example`):

| Var | Default | Notes |
|---|---|---|
| `DATABASE_URL` | — | required |
| `AUTH_SECRET` | — | **required**, min 32 chars — signs session tokens, never defaulted |
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
- **Money**: always integer cents (`cost_cents`), never a float — on both
  sides of the wire.
- **Secrets**: `AUTH_SECRET` is required with no fallback; passwords are
  bcrypt-hashed and `Workshop.PasswordHash` is `json:"-"` so it cannot be
  marshalled by accident.
- **Commits**: small, single-purpose, one-line message (imperative mood).
- **`internal/gen`**: generated from `proto/`, never hand-edited — run
  `make generate` after changing a `.proto` file.
