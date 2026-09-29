# Mototeca — Screen Mockups + Brand

Phone-sized (393×852) mockups of the screens of **two apps**, plus brand
colors/logo. Product context: [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

Live canvas: https://claude.ai/code/artifact/d6cc8a70-1503-4f85-ac17-220bb3a631cc

## Two apps, one history

The product ships as two Flutter apps, because the two profiles have opposite
rhythms: a rider opens the app a few times a year, a workshop opens it dozens of
times a day. A single app had to ask which one you were before showing anything,
and that question was a login screen at the root.

**Neither app opens on a login.** The root of both is a home screen listing what
already works with no account and no signal; "Entrar" is an action inside the
app, not a gate in front of it.

| | App Motociclista | App Oficina |
|---|---|---|
| Home | `Main.dc.html` | `ShopHome.dc.html` |
| Works with no account | garage, reminders, local maintenance notes | filling a service record, the outbox, a quick quote |
| Needs the network, not an account | plate lookup, service detail | plate lookup, service detail |
| What signing in adds | claiming a bike, the workshops' records, server backup | publishing the queue into the public history |
| Sign-in | celular + WhatsApp code (`OwnerLogin.dc.html`) | CNPJ + senha (`ShopLogin.dc.html`) |

Routes and flows for both: [`NAVIGATION.md`](NAVIGATION.md).

## About the files
`.dc.html` files are interactive HTML mockups — open in a browser, not
production code. They're the spec (colors, copy, layout, behavior) to rebuild as
Flutter widgets, not to port directly. Each screen is its own file;
`canvas.json` lays them out on one canvas, grouped by app. Screens don't
navigate to each other — that's the Flutter app's job.

## Screens

**App Motociclista**

1. **Início** (`Main.dc.html`) — the root: four things that work now, each tagged
   *Funciona offline* or *Precisa de internet*, then the card explaining what
   signing in adds.
2. **Entrar** (`OwnerLogin.dc.html`) — celular, then the WhatsApp code. Reached
   from the home, and "Continuar sem conta" goes back.
3. **Minha Garagem** (`MyVehicles.dc.html`) — bikes held on the device (*Só neste
   aparelho*) until an account syncs them; the claim dialog asks for the last 6
   of the chassi.
4. **Lembretes** (`Reminders.dc.html`) — computed from the km on the device.
5. **Consultar Placa** (`CustomerPortal.dc.html`) — no-login plate lookup, full
   cross-workshop service history. Present in both apps.

**App Oficina**

6. **Início** (`ShopHome.dc.html`) — the root: Novo Registro first, then the
   outbox, the quick quote and the plate lookup.
7. **Entrar** (`ShopLogin.dc.html`) — CNPJ + senha, and what happens to the queue
   afterwards.
8. **Novo Registro** (`NewRecord.dc.html`) — *principal funcionalidade*: search a
   vehicle by plate, select operation types (chips), fill km/cost/parts/notes,
   attach before/after photos. Saves into the outbox, signed in or not.
9. **Fila de Envio** (`Outbox.dc.html`) — records waiting on the device; nothing
   leaves it before an account is attached.
10. **Painel da Oficina** (`Dashboard.dc.html`) — this month's stat, queue state,
    buscar veículo, novo registro, recent records for the logged-in oficina.
11. **Cadastrar Oficina** (`WorkshopRegister.dc.html`).
12. **Corrigir Registro** (`ReviseRecord.dc.html`) — a correction is a new record
    that supersedes the original, which stays in the history pointing at it.

**Comum aos dois apps**

13. **Cadastrar Veículo** (`VehicleRegister.dc.html`) — placa, chassi, marca,
    modelo, ano (matches `CreateVehicleRequest` in `proto/`).
14. **Detalhe do Serviço** (`ServiceDetail.dc.html`).
15. **Sobre o App** (`About.dc.html`) — static: logo, the two apps, feature list,
    credits.

States captured live from each screen's own logic in `render.mjs`: the WhatsApp
code step, the synced garage, the "Adicionar moto" dialog with the chassi check,
the lower-mileage confirmation, the superseded-record banner and the outbox
draining after sign-in.

All mock data is hardcoded (3 sample vehicles). No real API calls, no
cross-screen routing.

## Design tokens

| Role | Color |
|---|---|
| Primary (petrol blue) | `#1B4965` |
| Primary hover | `#2D7AA9` |
| Primary tint | `#EAF3FA` / `#CFE4F2` |
| Accent (rust orange) | `#B84F20` |
| Graphite (text) | `#0F172A` |
| Slate 50/100/200/500 | `#F8FAFC` / `#F1F5F9` / `#E2E8F0` / `#64748B` |
| Success / Warning / Error | `#22C55E` / `#EAB308` / `#EF4444` |

The app badge in each header uses petrol for Motociclista, rust for Oficina and
slate for a screen that belongs to both. *Funciona offline* is a green pill,
*Precisa de internet* an amber one — offline is the norm, needing the network is
the exception worth flagging.

Full palette + usage rules: `Mototeca Brand.dc.html`. Fonts: Inter (UI text),
JetBrains Mono (plates, IDs, money). Radius 8–10px, border `#E2E8F0`, tap targets
≥44px, form inputs 16px (avoids mobile auto-zoom).

## Files
- The 15 screens listed above.
- `render.mjs` — renders every artboard (and the states above) to `exports/`
  (full height) and `exports-viewport/` (phone height), which is where the
  report's images come from.
- `canvas.json` — layout for the published canvas, grouped by app.
- `Mototeca Brand.dc.html` — palette + logo reference.
- `support.js`, `image-slot.js` — mockup runtime/component support files.
