# Backlog

Improvements found in the September 2026 review that are not built yet,
ordered by importance within each group. The items already done in that pass
(chassi proof on claim, per-account login lockout, odometer rollback check,
correcting and releasing from the app, several photos per phase, CI) are in
the git history.

## Security and trust

- **Verify workshops.** Any CNPJ that passes the check digits can write to the
  public history, and `workshops.verified` is never set. Look the CNPJ up
  against Receita Federal (or review sign-ups by hand), show unverified shops
  with a badge in the history, and consider hiding their records from the
  public lookup until verified.
- **Stronger ownership transfer.** Claiming now needs the last 6 characters of
  the chassi, but anyone who has seen the CRLV knows them. The ARCHITECTURE.md
  design is CPF + OTP, with the previous owner confirming the release.
- **Password reset, logout and revocation.** Tokens are self-contained and
  last 12h, so there is no server-side logout and a password change does not
  end other sessions. Add a `token_version` column checked on verify (or a
  session table) and a reset flow, which needs the SMS/e-mail sender below.
- **Owner sign-in by OTP (WhatsApp/SMS).** The intended design; blocked on
  choosing a provider. Password login stays as the fallback.
- **Lockout abuse.** The per-account login lock can be tripped on purpose to
  keep someone out for five minutes at a time. Progressive delays or a CAPTCHA
  after the first lock would blunt that.
- **Presigned photo URLs.** The bucket is anonymous-read; names are random
  UUIDs, which is obscurity, not authorization. Serve expiring presigned URLs
  from the API instead.
- **Rate limits behind a proxy.** Limits key on the TCP peer. Behind a load
  balancer everyone shares one IP: trust `X-Forwarded-For` only from a
  configured proxy, and move the buckets to Redis for more than one instance.
- **LGPD.** No account deletion or data export for owners. Mechanic names are
  shown in the public history; decide whether that is necessary or should be
  reduced to the workshop.

## Product

- **Reminders beyond oil.** One fixed 3,000 km oil interval for every bike.
  Store intervals per model and per service type (chain, brakes, review), and
  send push notifications when something is due.
- **Pagination.** Lists cap at 100 records with no cursor. Add a
  `page_token` (created_at + id) to the list RPCs and infinite scroll in the app.
- **Edit picked photos one by one.** A slot can only be cleared as a whole
  before saving, and saved photos cannot be removed from a record (only a
  correction adds to them).
- **QR code lookup** for the public history, as ARCHITECTURE.md describes.
- **Offline drafts.** A dropped connection loses a half-filled Novo Registro.
  Persist the draft locally and retry uploads (ARCHITECTURE.md §9).
- **Mechanic roles.** `mechanics.role` exists in the schema and is unused.

## Engineering

- **iOS target.** `mobile/` has no `ios/` folder, so the app cannot be built
  for iPhone even though the screens were designed for one. Run
  `flutter create --platforms=ios .` on a Mac and add the photo-library usage
  strings to `Info.plist`.
- **Upload integration test** against a real MinIO; today the route is covered
  by unit tests with fakes and by the e2e script.
- **Observability.** `/healthz` checks Postgres but not object storage, logs
  carry no request id, and there are no metrics (latency, error rate per RPC).
- **Recapture contract fixtures** in `mobile/test/fixtures/` whenever a proto
  changes; they were captured before the correction fields were added.
- **Local linters.** The installed `golangci-lint` and `staticcheck` were built
  with Go 1.25 and cannot analyse this Go 1.26 module; add them to CI with a
  current version instead.
- **Production setup.** Backups (ARCHITECTURE.md §7), TLS, a reverse proxy,
  secret management and `CORS_ALLOWED_ORIGINS` for the real web origin are
  documented but not provisioned.
