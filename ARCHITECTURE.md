# Architecture

## Two apps, one history

| | Mototeca Oficina | Mototeca Motociclista |
|---|---|---|
| User | mechanic, many times a day | owner, a few times a year |
| Sign-in | CNPJ + password | phone + password |
| Android flavor | `shop` (`.oficina`) | `rider` (`.motociclista`) |

Both apps are built from `mobile/` and talk to the same API. A screen goes in
`lib/shared/` only when both apps build it unchanged; otherwise each app has
its own screen.

```
mobile/lib/
  main_shop.dart, main_rider.dart   entry points
  app/       MaterialApp, flavor, route table per app
  shop/      Oficina-only screens
  rider/     Motociclista-only screens
  shared/    plate lookup, service detail, vehicle, about
  storage/   SQLite on the device: garage, notes and outbox
  api/, models/, repositories/      Connect-over-JSON client
  state/     session, repositories and stores (AppScope)
  demo/      in-app backend used when no API URL is given
```

### Offline first

The root `/` of each app is a home screen, never a login.

- **Oficina.** A service record can be filled with no account and no
  signal. It is saved to the *outbox* (`/fila`) on the device. Signing in, or
  tapping "Enviar tudo agora", uploads the queued records oldest first and
  removes each one that the API accepts.
- **Motociclista.** Bikes and maintenance notes are kept on the device and
  can be added, edited and deleted. Signing in shows the account's bikes and
  lets the owner claim one.

### Device database (mobile only)

The Go API never touches SQLite: it stores everything in PostgreSQL. SQLite
holds only what an app keeps on the phone before it reaches the API.

One SQLite file, `mototeca.db`, through `sqflite` (`lib/storage/database.dart`).
The web build runs the same SQLite as WebAssembly (`web/sqlite3.wasm`, from
`dart run sqflite_common_ffi_web:setup`). Foreign keys cascade deletes.

```
bikes              plate (unique), label, year, mileage_km
maintenance_notes  bike_id -> bikes, done_on, description, mileage_km, cost_cents
outbox_drafts      plate, vehicle_label, mileage_km, mechanic_name, cost_cents, notes, saved_at
outbox_operations  draft_id -> outbox_drafts, operation
outbox_parts       draft_id -> outbox_drafts, name, quantity, cost_cents
outbox_attachments draft_id -> outbox_drafts, kind, phase, filename, content_type, bytes
```

Plate lookup and service detail need the network but no account, in both apps.

### Routes

| Route | Oficina | Motociclista |
|---|---|---|
| `/` | home | home |
| `/entrar`, `/cadastro` | CNPJ sign-in, sign-up | phone sign-in, sign-up |
| `/painel` | dashboard | |
| `/registro/novo`, `/registro/corrigir` | new record, correction | |
| `/fila` | outbox | |
| `/garagem`, `/garagem/anotacoes`, `/lembretes` | | garage, notes, reminders |
| `/consulta`, `/servico`, `/veiculo/cadastro`, `/sobre` | shared | shared |

Screen mockups live in `design/` (`*.dc.html`, rendered by `design/render.mjs`).

## Client and API

The API is Go with [Connect-RPC](https://connectrpc.com). Connect accepts plain
JSON, so the apps call it with `package:http`: every call is
`POST /mototeca.<package>.<Service>/<Method>`. Dart models are written by hand.
Field names are camelCase. Errors arrive as `{"code","message"}` with a
non-2xx status, in Portuguese, ready to show.

Contracts are in `proto/`. `make generate` writes `internal/gen/`, which is
never edited by hand. Each domain in `internal/` (`vehicle`, `workshop`,
`owner`, `servicerecord`) has the same files: `types`, `validate`, `store`
(interface), `repository` (Postgres), `handler`. Unit tests use a fake store.
Tests tagged `integration` use a real database.

Photos do not go through RPC. They are uploaded as multipart to
`POST /v1/service-records/{id}/attachments` and stored in S3-compatible
storage.

## Data model

```
Vehicle       plate, chassi, make, model, year, current_owner_id
Owner         phone, name, password_hash
Workshop      cnpj, name, address, verified, password_hash
ServiceRecord vehicle, workshop, mechanic, mileage_km, cost_cents, notes, superseded_by
  operations  one or more from a fixed list (oil, brakes, tyres, ...)
  parts       name, quantity, cost_cents
  attachments photo (before/after) or invoice
```

Money is always integer cents.

## Rules that make the history trustworthy

- **Append-only.** A record is never edited. A correction writes a new record
  and sets `superseded_by` on the old one. Only the workshop that wrote a
  record can correct it.
- **Odometer.** A mileage below the bike's highest recorded value is refused.
  The mechanic must confirm a real cause before the app resends it.
- **Claiming a bike.** The plate is public, so a claim also needs the last 6
  characters of the chassi. When a bike is sold, the owner releases it and the
  history stays with the plate.
- **Public lookup** shows plate, make, model and year. It never shows the
  chassi or the owner.

## Security

- Bearer tokens are HMAC-signed and expire after 12 hours. Each token carries
  the account kind, so an owner token is rejected by workshop endpoints and
  the reverse. Account ids come from the token, never from the request.
- Passwords are stored as bcrypt hashes. Login gives the same error for an
  unknown account and a wrong password. Five failures lock that account for
  five minutes.
- Every endpoint is rate-limited per IP. The limits are stricter on logins,
  sign-ups, claims and the plate lookup. RPC bodies are capped at 1 MiB.
- Uploads are limited to 8 MiB and 20 files per record. The file type is
  detected from the content, and each file is stored under a random UUID name.
- `AUTH_SECRET` is required and has no default outside docker compose.

## Not built yet

- Uploading the outbox automatically when the connection returns.
- Merging the bikes saved on the device into the account after sign-in.
- Checking workshop CNPJs, sign-in by OTP, password reset, presigned photo
  URLs, iOS build.
