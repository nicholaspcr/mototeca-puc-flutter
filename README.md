# Mototeca

A shared service history for motorcycles in Brazil. Workshops record every job
in one place; owners see a bike's full history, across every workshop, by
plate.

## Two apps

Mechanics and riders use the product at very different rhythms, so it ships as
two Flutter apps built from one codebase. Neither opens on a login: the home
screen lists what works with no account and no signal, and signing in is an
action inside the app.

| | Mototeca Oficina | Mototeca Motociclista |
|---|---|---|
| For | the mechanic at the counter | the motorcycle owner |
| Works offline, no account | fill a service record, outbox | garage, reminders |
| Needs network, no account | plate lookup, service detail | plate lookup, service detail |
| Signing in | publishes the outbox to the history | syncs the garage, claims a bike |
| Entry point | `mobile/lib/main_shop.dart` | `mobile/lib/main_rider.dart` |

## Architecture

```
mobile/   Flutter: two apps, one codebase, device storage for offline work
   │  HTTP + JSON (Connect-RPC)
cmd/, internal/   Go API, stateless
   │
Postgres (records, append-only)  ·  S3-compatible storage (photos)
```

Details, rules and security decisions: [ARCHITECTURE.md](ARCHITECTURE.md).

## Run the mobile demos

The apps run with no backend: an in-app demo server (`mobile/lib/demo/`)
holds sample workshops, bikes and history. Reloading resets it.

```bash
cd mobile
flutter run -d chrome -t lib/main_shop.dart    # Mototeca Oficina
flutter run -d chrome -t lib/main_rider.dart   # Mototeca Motociclista
```

On Android, add `--flavor shop` or `--flavor rider`; both install side by side.

To sign in, tap **Entrar** and leave the fields blank. Sample data:

| | |
|---|---|
| Workshop | CNPJ `11222333000181`, password `senha-forte-123` |
| Owner | phone `31990001234`, password `senha-forte-123` |
| Bike | plate `ABC1D23`, chassi suffix `000001` |

To use the real API instead, start it and pass its URL:

```bash
docker compose up -d   # db, migrations, storage, API on :8080
cd mobile && flutter run -d chrome -t lib/main_shop.dart \
  --dart-define=MOTOTECA_API_URL=http://localhost:8080
```

## Tests

```bash
make test              # Go unit tests
make e2e               # every endpoint, against docker compose
cd mobile && flutter test
```
