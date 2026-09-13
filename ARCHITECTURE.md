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

- **Vehicle record** — identified by `placa` + `chassi`/RENAVAM (not internal IDs, so history follows the bike across shops). Make, model, year, color, owner, km history. Ownership transfer on sale: the seller releases the bike, the buyer claims it, and the service history is untouched.
- **Service history log** — date, oficina, mechanic, operation type (fixed taxonomy: troca de óleo, revisão programada, freios, corrente/relação/coroa, pneus, elétrica/bateria, velas, suspensão, embreagem, carburação/injeção, funilaria/pintura, outro), parts, labor, km, cost, before/after photos, notes. Append-only — edits create a new revision, never a mutation.
- **Oficina dashboard** — lookup by plate, create/edit only that shop's own records, customer list, orçamento draft → service record.
- **Customer portal** — plate or QR lookup, no account needed to view; phone/CPF+OTP only to claim ownership. Shareable PDF summary.
- **Notifications** — WhatsApp-first, reminders by km or elapsed time. Today
  the reminder is derived from the service history (mileage since the last oil
  change); nothing is actually sent yet.
- **Trust (later)** — oficina ratings, owner confirmation step on entries.

## 4. Data Model

```
Vehicle        (plate, chassi, make, model, year, current_owner_id)
Owner          (phone, cpf_hash?, name, password_hash)
Workshop       (cnpj, name, address, verified, password_hash)
Mechanic       (workshop_id, name, role)
ServiceRecord  (vehicle_id, workshop_id, mechanic_id, mileage_km,
                cost_cents, notes, superseded_by, created_at)
ServiceRecordOperation (service_record_id, type)
Part           (service_record_id, name, quantity, cost_cents)
Attachment     (service_record_id, url, kind: photo|invoice, phase: before|after)
```

A record carries **several** operations, not one — the Novo Registro screen
lets a mechanic tick more than one, so the type lives in a join table rather
than a column. `phase` is what makes "antes/depois" expressible; `kind` only
separates a photo from an invoice. Money is integer cents everywhere.

## 5. Mobile Client: Flutter

Course requirement, not an open choice: one Flutter app (Android-first) for both personas, role/login screen routes into the mechanic or owner flow — mirrors `design/Mototeca App.dc.html`.

Talks to the Go API over plain HTTP+JSON: Connect-RPC already accepts `Content-Type: application/json` on the same endpoints it serves gRPC/gRPC-Web on, so `package:http` + `dart:convert` is enough — no codegen, no separate REST layer. Trade-off: RPC-shaped URLs (`POST /<Service>/<Method>`) and hand-written Dart models. See the README's "Calling the API" section for exact shapes.

Flutter code lives under `mobile/`; `design/` is the mockup/brand reference and `design/NAVIGATION.md` is the screen/route map. Every screen calls the API — the app carries no sample data.

## 6. Backend & Infrastructure

- **Go** API at repo root (`go.mod`, `cmd/`, `internal/`), static binary.
- **Postgres** — relational data, append-only trust ledger. Schema/migrations in `db/migrations`, tracked in `schema_migrations` and applied by a one-shot compose service before the API starts.
- Object storage (S3-compatible) for photos/attachments — MinIO in compose,
  reached over a multipart route rather than an RPC so bytes are not
  base64-inflated. Anonymous-read bucket, since the history it hangs off is
  public; presigned URLs are the hardening step.
- Stateless API, horizontally scalable.
- Auth: CNPJ + password for oficinas, phone + password for owners. bcrypt
  digests, HMAC-signed bearer tokens with a 12h expiry and no session table.
  The token carries the account kind, so the two flows cannot borrow each
  other's sessions. Phone+OTP is the eventual design for owners; it needs an
  SMS/WhatsApp sender, so a password stands in for now. The `verified` flag on
  a workshop is separate from authentication — signing in does not mean the
  CNPJ was checked.

## 7. Backups

Daily full snapshot + WAL/point-in-time recovery, 30-day rolling window + monthly archives, stored off-provider. Object storage versioned separately. Quarterly restore drills.

## 8. Security & Privacy (LGPD)

- CPF/phone/vehicle data is personal data: minimize collection, hash/encrypt CPF at rest, define retention.
- Owner consent before linking a workshop entry to their identity; shared history links never leak owner PII.
- Rate-limit plate lookups. Implemented per client IP, in-process, on every
  endpoint, tighter on the plate lookup, logins and signups; a multi-instance
  deployment needs a shared store instead.
- The public plate lookup returns a reduced vehicle (plate, make, model, year)
  — never the chassi or the owner. The full vehicle, chassi included, needs a
  workshop session, and owner ids never leave the server.
- Uploaded files are typed by content sniffing, not by what the client claims.
- Claiming a bike needs the end of its chassi, since the plate is public;
  CPF + OTP with the seller's confirmation is the stronger design (BACKLOG.md).
- Repeated failed logins lock the account for a few minutes, independent of
  the caller's address.

## 9. Low-Bandwidth Considerations

Lazy-load/compress images. Local draft persistence for forms (flaky oficina connections). Avoid real-time features unless genuinely needed — poll or reload instead.

## 10. Repo Layout & Local Development

```
mototeca/
  go.mod, cmd/, internal/, db/migrations/   Go API, at repo root
  design/                                   screen mockups + brand tokens (not code)
  mobile/                                   Flutter app
  scripts/e2e.sh                            asserts the response of every endpoint
```

```bash
cp .env.example .env   # set DATABASE_URL and AUTH_SECRET
make db-up              # local Postgres
make migrate             # applies pending db/migrations/*.sql
make run                  # starts the API on :8080
make test                 # scoped to ./cmd/... ./internal/...
make test-integration     # + DB-backed tests, needs `make db-up` first
make e2e                  # asserts every endpoint against `docker compose up -d`

cd mobile && flutter test  # API client, contract and navigation tests
```

`internal/vehicle` (types → validation → store → repository → handler) is the template every domain follows; `internal/workshop` and `internal/servicerecord` were built from it.
