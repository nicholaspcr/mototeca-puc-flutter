# Mototeca — Screen Mockups + Brand

Phone-sized (393×852) mockups of the app's screens, plus brand colors/logo. Product context: [`../ARCHITECTURE.md`](../ARCHITECTURE.md).

Live canvas: https://claude.ai/code/artifact/d6cc8a70-1503-4f85-ac17-220bb3a631cc

## About the files
`.dc.html` files are interactive HTML mockups — open in a browser, not production code. They're the spec (colors, copy, layout, behavior) to rebuild as Flutter widgets, not to port directly. Each screen is its own file; `canvas.json` lays them out on one canvas. Screens don't navigate to each other — that's the Flutter app's job.

## Screens

1. **Login / Home** (`Main.dc.html`) — role toggle (oficina / proprietário) switches the login form fields (CNPJ+senha vs. celular+OTP).
2. **Mechanic Dashboard** (`Dashboard.dc.html`) — this month's stat, buscar veículo, novo registro, recent service records for the logged-in oficina.
3. **New Service Record** (`NewRecord.dc.html`) — *principal funcionalidade*: search a vehicle by plate, select operation types (chips), fill km/cost/parts/notes, attach before/after photos.
4. **Customer Portal** (`CustomerPortal.dc.html`) — no-login plate lookup, full cross-workshop service history.
5. **Cadastro de Veículo** (`VehicleRegister.dc.html`) — register a vehicle (placa, chassi, marca, modelo, ano — matches `CreateVehicleRequest` in `proto/`).
6. **Sobre o App** (`About.dc.html`) — static: logo, description, feature list, credits.
7. **Corrigir Registro** (`ReviseRecord.dc.html`) — a correction is a new record that supersedes the original, which stays in the history pointing at it.

Three states worth capturing live inside the screens above, driven by their own logic in `render.mjs`: the lower-mileage confirmation (New Record), the "Adicionar moto" dialog with the chassi check (Minhas Motos) and the superseded-record banner (Detalhe do Serviço).

All mock data is hardcoded (3 sample vehicles). No real API calls, no cross-screen routing.

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

Full palette + usage rules: `Mototeca Brand.dc.html`. Fonts: Inter (UI text), JetBrains Mono (plates, IDs, money). Radius 8–10px, border `#E2E8F0`, tap targets ≥44px, form inputs 16px (avoids mobile auto-zoom).

## Files
- `Main.dc.html`, `WorkshopRegister.dc.html`, `Dashboard.dc.html`, `NewRecord.dc.html`, `VehicleRegister.dc.html`, `MyVehicles.dc.html`, `CustomerPortal.dc.html`, `ServiceDetail.dc.html`, `Reminders.dc.html`, `About.dc.html`, `ReviseRecord.dc.html` — the 11 screens.
- `render.mjs` — renders every artboard (and the states above) to `exports/` (full height) and `exports-viewport/` (phone height), which is where the tp-2 report's images come from.
- `canvas.json` — layout for the published canvas.
- `Mototeca Brand.dc.html` — palette + logo reference.
- `support.js`, `image-slot.js` — mockup runtime/component support files.
