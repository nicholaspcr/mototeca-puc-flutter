# Mototeca — Architecture

## 1. Purpose

Mototeca is a cloud system that stores the service/repair history of motorcycles
(`motocicletas`, `motos`) in Brazil. It sits between workshops (`oficinas`) and
owners (`proprietários`):

- **Mechanics** log every operation performed on a bike in one shared place,
  instead of a paper `caderneta` or a spreadsheet per shop.
- **Owners** can check a bike's full history — regardless of which oficina did
  the work — from a phone, mainly to build trust and support resale value
  (a "Carfax for motorcycles" angle).

Primary market: Brazil. Two user surfaces (mechanic-facing, customer-facing),
one shared history record per vehicle.

## 2. Personas

| Persona | Context | Primary device |
|---|---|---|
| Mecânico / Oficina | Small independent shop, 1–10 employees, often shared PC at the counter | Low-spec desktop/laptop, older browser |
| Proprietário (owner) | Checks history occasionally, usually after a service or before buying/selling | Mid/low-end Android phone |
| Admin (Mototeca) | Support, moderation, dispute resolution | Any |

The mechanic is the daily, high-frequency user and the data entry point. The
owner is a low-frequency, read-mostly user. These two profiles should drive
every UX and stack decision below — they are not the same problem.

## 3. Core Features (MVP)

### 3.1 Vehicle record
- Vehicle identified by `placa` (plate) and `chassi`/RENAVAM, not by internal
  workshop IDs — this is what lets history follow the bike across oficinas.
- Basic profile: make, model, year, color, current owner, mileage (`km`)
  history.
- Ownership transfer flow: current owner can hand off/revoke access when the
  bike is sold.

### 3.2 Service history log
Every visit becomes a record with:
- Date, oficina, mechanic responsible.
- Operation type, from a fixed taxonomy so history stays structured and
  searchable rather than free text, e.g.:
  - Troca de óleo e filtro
  - Revisão programada (by km/time)
  - Freios (pastilhas, discos, fluido)
  - Corrente, relação e coroa
  - Pneus
  - Elétrica / bateria
  - Velas / ignição
  - Suspensão
  - Embreagem
  - Carburação / injeção eletrônica
  - Funilaria / pintura (post-accident)
  - Outro (free text, tagged for later taxonomy review)
- Parts replaced, labor description, mileage at service, cost, photos
  (before/after), free-text notes.
- Optional link to `Nota Fiscal` (NFS-e) — phase 2, not MVP-blocking.

### 3.3 Mechanic / oficina dashboard
- Vehicle lookup by plate/chassi (the daily core action).
- Create/edit service records for that shop's own entries (shops cannot edit
  another shop's history — append-only across oficinas, preserves trust).
- Simple customer list per shop, quick "repeat last service" for common jobs.
- Orçamento (quote) draft that can convert into a service record once
  approved.

### 3.4 Customer portal
- Look up a bike's full history via plate, or via a QR code sticker/link
  the oficina can hand over or stick on the bike.
- No mandatory account creation to *view* a history behind a shared link;
  account (phone/CPF + OTP) required to claim ownership and manage access.
- Downloadable/shareable PDF summary — useful for resale.

### 3.5 Notifications
- WhatsApp is the dominant channel in Brazil — prioritize WhatsApp
  (Business API) over email/SMS/push for service reminders and "your bike's
  service is ready" messages.
- Reminders based on km or elapsed time since last service of a given type.

### 3.6 Trust & verification (phase 2)
- Oficina profile with rating/reviews tied to verified completed services.
- Optional owner confirmation step ("did this service happen?") to prevent
  fraudulent history entries inflating resale value.

## 4. Data Model (high level)

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

`ServiceRecord` should be append-only/immutable once submitted (edits create
a new revision, not a mutation) — this is what makes the history trustworthy
across shops.

## 5. Mobile Client Strategy: Flutter

### Constraint
This project is built for a "Desenvolvimento Móvel" (Mobile Development)
discipline whose objective is a **Flutter mobile app** — that is a fixed
requirement, not an open architecture choice. Both personas therefore share
one Flutter codebase (Android primarily, since that's what both oficina
staff and owners actually carry) rather than a browser-based dashboard for
one side and a native app for the other:

- **Mecânico / Oficina**: small shops (1–10 employees) increasingly run the
  counter off a phone or tablet rather than a fixed PC — Flutter targets
  that hardware natively (camera access for before/after photos, works
  acceptably offline between requests).
- **Proprietário (owner)**: already assumed a mid/low-end Android phone —
  a natural fit for a Flutter app instead of a one-off browser visit.

### Why not a browser app
A server-rendered/PWA web frontend (the original plan for this sketch,
before it was scoped into the Mobile Development discipline — see
`design/`, which still reflects that earlier direction) would have been a
reasonable choice on product merits alone: no install friction, lighter to
build for old hardware. It's not compatible with the discipline's graded
deliverable, though, so it's out of scope here. The camera-heavy mechanic
flow (photos of invoices and completed work) and the km/time-based
notifications for owners both map onto native mobile capabilities Flutter
gives for free (camera plugin, local notifications), which softens the loss.

### Implementation notes
- One Flutter app, both personas — a role/login screen routes into the
  mechanic flow or the owner flow, mirroring the two-persona split already
  in `design/Mototeca App.dc.html`.
- Talks to the Go API over plain HTTP+JSON (Connect protocol — see §6), no
  generated client required to start.
- **Decided: keep the Connect-RPC/protobuf backend as-is, don't add a
  separate REST layer.** Connect already accepts `Content-Type:
  application/json` on the same endpoints it serves gRPC/gRPC-Web on, so the
  simplest Flutter setup — `package:http` + `dart:convert`, no codegen — is
  available for free. The only cost is an RPC-shaped URL
  (`POST /<Service>/<Method>` instead of REST resource paths) and hand-
  written Dart models instead of generated ones; see the README's "Calling
  the API" section for the exact request/response shapes.
- Screens/navigation for course deliverables live under a `mobile/` (or
  similar) Flutter project inside this repo, per the top-level README;
  `design/` is the mockup/brand reference to build them from, not code to
  port directly (see `design/README.md`).

## 6. Backend & Infrastructure

Backend and mobile client are deliberately separate: a Go API service and a
Flutter app talking to it over HTTP, not a single full-stack app:

- **Backend: Go**, a standalone HTTP API living at the repo root as a normal
  Go module (`go.mod`, `cmd/`, `internal/`). Compiles to a static binary —
  small memory footprint, fast cold start, cheap to run on modest hardware,
  which matters for a cost-sensitive MVP. (Rust would run even leaner but
  costs more development time than an MVP here justifies — Go is the better
  trade for now.)
- **Mobile client: Flutter** (planned — not yet in this repo, see §5), no
  direct database access. It calls the Go API over HTTP using the Connect
  protocol (protobuf-defined, but also speaks plain JSON — see `proto/`).
- Postgres — the data is inherently relational (vehicle → records →
  parts/attachments) and needs integrity guarantees for an append-only trust
  ledger. Backend owns the schema and migrations (`db/migrations`).
- Object storage (S3-compatible) for photos/attachments, not in the DB.
- Stateless API layer, horizontally scalable.
- Auth: phone number + OTP for owners (matches WhatsApp-first Brazilian
  habits); CNPJ-verified onboarding for oficinas to keep shop identity real.

## 7. Backups & Disaster Recovery

- Automated daily full DB snapshot + continuous WAL/point-in-time recovery,
  retained on a rolling window (e.g. 30 days) plus monthly archives kept
  longer.
- Backups stored off-provider (different region/provider than primary DB) —
  a provider-level outage should not take out backups too.
- Object storage (photos) versioned/replicated separately from DB backups.
- Scheduled restore drills (e.g. quarterly): a backup that has never been
  restored is unverified. Track restore time to have a real RPO/RTO number,
  not an assumed one.
- Service records are the trust asset of the whole product — losing them is
  losing the reason customers use Mototeca at all, so this is not optional
  for MVP scope even though it's invisible to users.

## 8. Security & Privacy (LGPD)

- CPF, phone number, and vehicle data are personal data under Brazil's LGPD:
  minimize what's collected, hash/encrypt CPF at rest, define retention and
  deletion policy up front.
- Owner consent required before a workshop's entry is linked to their
  identity; shared-link history views should avoid leaking owner PII to
  anonymous viewers (show vehicle history, not the owner's phone/CPF).
- Rate-limit plate lookups to prevent scraping the whole vehicle history
  database.

## 9. Low-Bandwidth Considerations (summary)

- Lazy-load and compress images (photos are the heaviest asset type here).
- Design forms to tolerate connection drops: local draft persistence so a
  half-filled service record isn't lost on a flaky oficina connection.
- Avoid real-time features (websockets/live updates) unless a feature
  genuinely needs them — polling or plain reload is cheaper on unreliable
  mobile connections.

## 10. Suggested Phasing

**MVP**: vehicle record, service history log with fixed operation taxonomy,
mechanic dashboard, customer read-only history view via plate/QR, WhatsApp
reminders, backups, Flutter app (course deliverable).

**Phase 2**: orçamento → service record conversion, oficina ratings, Nota
Fiscal linking, ownership-transfer flow, offline capture for mechanics on
the shop floor.

## 11. Repo Layout & Local Development

```
mototeca/
  go.mod, cmd/, internal/, db/migrations/   Go API — normal Go project, at repo root
  design/                                   screen mockups + brand tokens (not code)
  mobile/                                   Flutter app — not started yet
```

Backend (from repo root):
```
cp .env.example .env   # set DATABASE_URL
make migrate            # applies db/migrations/0001_init.sql
make run                 # starts the API on :8080
make test                # scoped to ./cmd/... ./internal/...
make test-integration    # same scope, plus the `integration` build tag — needs
                          # `make db-up` first; make test alone stays DB-free
```

The `vehicle` vertical slice (types → validation → repository → HTTP
handler in `internal/vehicle`) is the template to follow when adding the
next domain (service records, workshops, owners). No client consumes it yet
— the Flutter app will, once started (see §5).
