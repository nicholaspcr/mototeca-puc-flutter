# Mototeca

Service/repair history for motorcycles in Brazil — mechanics log work, owners
look up a bike's full history by plate. See [ARCHITECTURE.md](ARCHITECTURE.md)
for the product/domain context, data model, and infra rationale. This file is
the "get running" doc.

This repo holds the **Go backend API** (repo root) and the **Flutter app**
(`mobile/`). Every screen runs against the real API — there is no sample data
left in the app. `design/` holds the screen mockups the UI was built from.

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
| `owner.v1.OwnerService/CreateOwner` | public | Criar Conta |
| `owner.v1.OwnerService/Login` | public | Login (proprietário) |
| `owner.v1.OwnerService/ListMyVehicles` | **owner token** | Minhas Motos, Lembretes |
| `owner.v1.OwnerService/ClaimVehicle` | **owner token** + chassi suffix | Cadastrar nova moto |
| `owner.v1.OwnerService/ReleaseVehicle` | **owner token** | venda da moto |
| `vehicle.v1.VehicleService/CreateVehicle` | **workshop or owner token** | Cadastrar Veículo |
| `vehicle.v1.VehicleService/GetVehicleByPlate` | **workshop token** | Novo Registro (busca) |
| `service.v1.ServiceRecordService/CreateServiceRecord` | **workshop token** | Novo Registro (salvar) |
| `service.v1.ServiceRecordService/ListWorkshopServiceRecords` | **workshop token** | Painel da Oficina |
| `service.v1.ServiceRecordService/ReviseServiceRecord` | **workshop token** | correção de um registro |
| `service.v1.ServiceRecordService/ListServiceRecordsByPlate` | public | Portal do Proprietário |
| `service.v1.ServiceRecordService/GetServiceRecord` | public | Detalhe do Serviço |

`GetVehicleByPlate` needs a workshop session because it returns the chassi;
the public lookup is `ListServiceRecordsByPlate`, which never does.
`CreateVehicle` needs a session so nobody can squat a plate anonymously, and
answers `already_exists` for a registered plate or chassi — which is how the
owner app knows to claim the bike instead.

Error messages are written for the app's users, in Portuguese, and shown as
they arrive.

All procedure names are prefixed with `mototeca.` — e.g.
`POST /mototeca.workshop.v1.WorkshopService/Login`.

### Photo upload

One route is not an RPC: `POST /v1/service-records/{id}/attachments`, multipart,
with the same bearer token. Protobuf would carry the bytes base64-encoded —
a third larger and entirely in memory — so photos stream instead. Fields:
`file` (required), `kind` (`photo` default, or `invoice`), `phase`
(`before`/`after`, photos only).

Ownership is checked before the body is read. Files go to S3-compatible
storage (MinIO in compose), capped at 8 MiB, with an allowlist of
jpeg/png/webp/pdf. The type is sniffed from the bytes, never taken from the
client, so an HTML page labelled `image/png` is refused. The stored name is a
generated UUID — never the client's filename — so an upload cannot overwrite
another or smuggle a path. A record holds at most 20 files. If linking the file
to the record fails, the stored object is deleted. Success and failure bodies match the Connect shape, so the
client parses them the same way.

The bucket is anonymous-read: the plate lookup is public, so the photos on it
must be too. Names are unguessable UUIDs, but that is obscurity rather than
authorization — presigned expiring URLs are the hardening step if photos ever
carry anything sensitive. Without `STORAGE_ENDPOINT` the API starts normally
and only this route is absent.

### Corrections are append-only

A record is never edited. `ReviseServiceRecord` writes a new one and points the
original at it via `superseded_by`, in one transaction; lists then show only
rows where `superseded_by IS NULL`. The superseded row stays in the table, so
the trail is auditable — which is the whole basis for trusting history written
by a shop you've never met. Only the workshop that wrote a record can revise
it, and only once: the correction is what gets corrected next. Photos and the
invoice carry over to the correction, and an owner's odometer and reminders
ignore superseded rows. A superseded record reached by id carries
`supersededByRecordId`, so an old link leads to its correction.

### Odometer rollback

`CreateServiceRecord` refuses a mileage below the bike's highest recorded one
with `failed_precondition` — a rolled-back odometer is the fraud a shared
history exists to expose. The app shows the refusal and resends with
`confirmLowerMileage: true` only after the mechanic confirms a real cause,
such as a replaced instrument cluster. Corrections are exempt: fixing a typo
is their purpose.

### Claiming a bike

A plate is public, so it cannot prove ownership. `ClaimVehicle` also takes
`chassiSuffix`, the last 6 characters of the chassi printed on the registration
document, checked before anything about the current owner is revealed. It is
rate-limited per IP. `ReleaseVehicle` unlinks a sold bike for the buyer to
claim; the history stays with the plate.

### Auth

Signing up or signing in returns a `token`; send it back as
`Authorization: Bearer <token>`. It is an HMAC-signed string carrying the
account **kind** (workshop or owner), its id, and an expiry (12h), so verifying
costs no database round-trip — the trade-off is that it cannot be revoked
before it expires. Passwords are bcrypt digests.

The kind is inside the signed payload, so an owner's token is rejected on a
workshop endpoint and vice versa. A workshop can only write records under its
own name, and an owner only sees their own bikes: both ids come from the token,
never from the request body.

Every login returns the same `unauthenticated` error for an unknown
CNPJ/phone as for a wrong password, so it can't be used to discover who is
registered. Five failures in a row lock that CNPJ or phone for five minutes,
whatever address the guesses come from; unregistered identifiers lock the
same way, so a lock reveals nothing. Every endpoint is also rate-limited per
client IP, tighter on logins, signups, claims and the public plate lookup
(in-process — a multi-instance deployment needs a shared store). RPC bodies
are capped at 1 MiB.

### Browsers (CORS)

The Flutter web build calls the API from another origin. With
`CORS_ALLOWED_ORIGINS` unset only `localhost` origins are allowed, which covers
`flutter run -d chrome`; set it to a comma-separated list in production.
Sessions travel in the `Authorization` header, never in cookies, so a foreign
page has no credentials to ride.

## Calling the API (Flutter side)

Every RPC is a `POST` to `/<package>.<Service>/<Method>` with
`Content-Type: application/json`. No gRPC/Connect client library needed —
`package:http` + `dart:convert` is enough.

```bash
TOKEN=$(curl -s http://localhost:8080/mototeca.workshop.v1.WorkshopService/Login \
  -H "Content-Type: application/json" \
  -d '{"cnpj":"11222333000181","password":"senha-forte-123"}' | jq -r .token)

curl -s http://localhost:8080/mototeca.vehicle.v1.VehicleService/CreateVehicle \
  -H "Content-Type: application/json" -H "Authorization: Bearer $TOKEN" \
  -d '{"plate":"ABC1D23","chassi":"9BWZZZ377VT004251","make":"Honda","model":"CG 160","year":2022}'
# -> {"vehicle":{"id":"...","plate":"ABC1D23","chassi":"9BWZZZ377VT004251","make":"Honda","model":"CG 160","year":2022,"createdAt":"2026-08-30T12:00:00Z"}}

curl -s http://localhost:8080/mototeca.service.v1.ServiceRecordService/ListServiceRecordsByPlate \
  -H "Content-Type: application/json" \
  -d '{"plate":"ABC1D23"}'
```

Two things to know when mirroring these shapes in Dart models:
- Protobuf JSON uses **camelCase** field names, not the `snake_case` seen in
  `.proto` (`mileage_km` → `mileageKm`, `created_at` → `createdAt`).
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
make migrate                 # applies pending db/migrations/*.sql

# 2. Backend — starts API on :8080
export AUTH_SECRET="$(openssl rand -base64 48)"   # or set it in .env
make run

# 3. Flutter app (separate terminal)
cd mobile && flutter run -d chrome
```

Everything in one place instead, API included:

```bash
docker compose up -d          # db, migrations, storage, api
make e2e                       # asserts every endpoint against it
```

See [mobile/DEMO.md](mobile/DEMO.md) for running the app in class, and
[BACKLOG.md](BACKLOG.md) for what is known and not built yet.

GitHub Actions (`.github/workflows/ci.yml`) runs the Go unit and integration
tests, `flutter analyze` and `flutter test`, and `make e2e` against the compose
stack on every push to `main` and every pull request.

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
  workshop/            oficina signup + login
  owner/               proprietário signup + login, their bikes, reminders
  servicerecord/       the core: records, operations, parts
  storage/             S3-compatible object storage for photos
  gen/                 generated Go protobuf/Connect code — do not edit
proto/mototeca/…/*.proto   API contracts, source of truth for gen/
db/migrations/       plain SQL migrations, tracked in schema_migrations
scripts/migrate.sh   applies pending migrations (`make migrate`, compose `migrate` service)
scripts/e2e.sh       asserts the response of every endpoint (see `make e2e`)
mobile/              the Flutter app
design/              screen mockups + brand tokens — not app code, the reference the UI was built from
```

### The Flutter app

```
lib/api/           ApiClient (Connect-over-JSON) + typed ApiException
lib/models/        Dart mirrors of the proto messages, hand-written
lib/repositories/  one per service — where procedure names live
lib/state/         AppScope/AppState — the session and the repositories
lib/reports/       the plate history PDF, built on the device
lib/screens/       one file per screen, matching design/NAVIGATION.md
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
make test-integration-docker  # the same, run inside the compose network
make generate             # buf generate — regenerate Go code from proto/

make db-up / db-down / db-logs   # local Postgres container
make migrate                      # apply pending db/migrations/*.sql
make e2e                           # assert every endpoint (needs `docker compose up -d`)

cd mobile && flutter test          # API client, contract and navigation tests
cd mobile && flutter analyze
```

## Configuration

Backend env vars (`.env`, see `.env.example`):

| Var | Default | Notes |
|---|---|---|
| `DATABASE_URL` | — | required |
| `AUTH_SECRET` | — | **required**, min 32 chars — signs session tokens, never defaulted |
| `STORAGE_ENDPOINT` | — | object storage host:port; empty disables photo upload |
| `STORAGE_ACCESS_KEY` / `STORAGE_SECRET_KEY` | — | required when storage is enabled |
| `STORAGE_BUCKET` | — | required when storage is enabled |
| `STORAGE_PUBLIC_URL` | — | how clients reach the bucket (differs from the internal endpoint) |
| `STORAGE_USE_SSL` | `false` | `true` for an https endpoint |
| `CORS_ALLOWED_ORIGINS` | — | comma-separated browser origins; empty allows `localhost` only, `*` any |
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
