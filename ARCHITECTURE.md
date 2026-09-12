# Mototeca — Architecture

## 1. Purpose

Mototeca stores motorcycle service/repair history in Brazil. Mechanics (`oficinas`) log every service in one shared place; owners (`proprietários`) check a bike's full history — across any oficina — from their phone.

## 2. Personas

| Persona | Context | Device |
|---|---|---|
| Mecânico / Oficina | Small shop, 1–10 employees | Phone/tablet at the counter |
| Proprietário | Checks history occasionally | Android phone |
| Admin | Support, moderation | Any |

## 3. Core Features

- **Vehicle record** — identified by `placa` + `chassi`/RENAVAM (not internal IDs, so history follows the bike across shops). Make, model, year, color, owner, km history. Ownership transfer on sale.
- **Service history log** — date, oficina, mechanic, operation type (fixed taxonomy: troca de óleo, revisão programada, freios, corrente/relação/coroa, pneus, elétrica/bateria, velas, suspensão, embreagem, carburação/injeção, funilaria/pintura, outro), parts, labor, km, cost, before/after photos, notes. Append-only — edits create a new revision, never a mutation.
- **Oficina dashboard** — lookup by plate, create/edit only that shop's own records, customer list, orçamento draft → service record.
- **Customer portal** — plate or QR lookup, no account needed to view; phone/CPF+OTP only to claim ownership. Shareable PDF summary.
- **Notifications** — WhatsApp-first, reminders by km or elapsed time.
- **Trust (later)** — oficina ratings, owner confirmation step on entries.

## 4. Data Model

```
Vehicle        (plate, chassi, make, model, year, current_owner_id)
Owner          (phone, cpf_hash, name)
Workshop       (cnpj, name, address, verified)
Mechanic       (workshop_id, name, role)
ServiceRecord  (vehicle_id, workshop_id, mechanic_id, type, mileage_km,
                cost, notes, created_at, immutable_at)
Part           (service_record_id, name, quantity, cost)
Attachment     (service_record_id, url, kind: photo|invoice)
```

## 5. Mobile Client: Flutter

Course requirement, not an open choice: one Flutter app (Android-first) for both personas, role/login screen routes into the mechanic or owner flow — mirrors `design/Mototeca App.dc.html`.

Talks to the Go API over plain HTTP+JSON: Connect-RPC already accepts `Content-Type: application/json` on the same endpoints it serves gRPC/gRPC-Web on, so `package:http` + `dart:convert` is enough — no codegen, no separate REST layer. Trade-off: RPC-shaped URLs (`POST /<Service>/<Method>`) and hand-written Dart models. See the README's "Calling the API" section for exact shapes.

Flutter code lives under `mobile/`; `design/` is the mockup/brand reference and `design/NAVIGATION.md` is the screen/route map to implement.

## 6. Backend & Infrastructure

- **Go** API at repo root (`go.mod`, `cmd/`, `internal/`), static binary.
- **Postgres** — relational data, append-only trust ledger. Schema/migrations in `db/migrations`.
- Object storage (S3-compatible) for photos/attachments.
- Stateless API, horizontally scalable.
- Auth: phone+OTP for owners, CNPJ-verified onboarding for oficinas.

## 7. Backups

Daily full snapshot + WAL/point-in-time recovery, 30-day rolling window + monthly archives, stored off-provider. Object storage versioned separately. Quarterly restore drills.

## 8. Security & Privacy (LGPD)

- CPF/phone/vehicle data is personal data: minimize collection, hash/encrypt CPF at rest, define retention.
- Owner consent before linking a workshop entry to their identity; shared history links never leak owner PII.
- Rate-limit plate lookups.

## 9. Low-Bandwidth Considerations

Lazy-load/compress images. Local draft persistence for forms (flaky oficina connections). Avoid real-time features unless genuinely needed — poll or reload instead.

## 10. Repo Layout & Local Development

```
mototeca/
  go.mod, cmd/, internal/, db/migrations/   Go API, at repo root
  design/                                   screen mockups + brand tokens (not code)
  mobile/                                   Flutter app — not started yet
```

```bash
cp .env.example .env   # set DATABASE_URL
make migrate            # applies db/migrations/0001_init.sql
make run                 # starts the API on :8080
make test                # scoped to ./cmd/... ./internal/...
make test-integration    # + DB-backed tests, needs `make db-up` first
```

`internal/vehicle` (types → validation → repository → handler) is the template for the next domain (service records, workshops, owners).
