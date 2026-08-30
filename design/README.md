# Handoff: Mototeca — Mobile Screen Mockups + Brand Identity

## Overview
Mototeca is a Brazilian cloud service that lets motorcycle workshops (`oficinas`) log every maintenance/repair service against a bike (identified by plate/`placa`), and lets owners look up a bike's full cross-workshop service history. This bundle contains phone-sized mockups of the core screens plus a first pass at brand color palette + logo.

Full product/technical context (personas, data model, backend/mobile stack decisions, LGPD/privacy notes, phasing) lives in [`../ARCHITECTURE.md`](../ARCHITECTURE.md) at the repo root — read that first for the "why" behind the screens.

Live canvas (view + PNG/PDF export): https://claude.ai/code/artifact/d6cc8a70-1503-4f85-ac17-220bb3a631cc

## About the Design Files
The `.dc.html` files in this bundle are **design references built in a proprietary HTML prototyping format** — they render standalone in a browser (open directly, no build step) but are NOT production code to copy/paste. Treat them purely as a visual and behavioral spec: colors, typography, spacing, copy, and screen flow. The task is to **rebuild these screens as Flutter widgets**, translating the layout/component intent (cards, buttons, inputs, chips, badges) into Flutter's own widget set, not by embedding or porting this HTML wholesale.

Each screen is its own file, sized to a 390×844 phone frame (`canvas.json` lays all four out side by side). They were reworked from an earlier desktop/web-console draft into this phone-shaped form once the project was scoped into a Mobile Development discipline that requires a **Flutter** app (`ARCHITECTURE.md` §5) — single-column layouts, 44px+ touch targets, 16px form inputs (avoids mobile-browser auto-zoom-on-focus), no fixed multi-column grids, no fake OS status bar/keyboard chrome.

## Fidelity
**Mix.** Colors, typography, spacing, and component chrome (cards, buttons, inputs, badges) are intentionally specific — treat those as close to final. Copy is real Portuguese microcopy, not lorem ipsum — reuse it. However: **this is explicitly an early sketch**, not a finished design —
- Only 4 of the 5 planned screens are mocked (Login/Home, Mechanic Dashboard, New Service Record, Customer Portal). No dedicated "Sobre o App" (about) screen, no standalone vehicle-registration ("cadastro") screen — vehicle creation today only happens as a fallback inside the New Service Record flow — no executions-list-equivalent ("Todas as Oficinas"/admin), no ownership-transfer flow, no orçamento (quote) flow. Those are open gaps against the course's screen requirements and/or Phase 2 per `ARCHITECTURE.md` §10 — not designed yet.
- All data is hardcoded mock data (3 fictional vehicles, 1 fictional workshop) — there is no real API integration, loading states, or error states designed yet.
- Each screen is its own artboard/file with its own local state — there is no cross-screen navigation wired up in this bundle (a login "Entrar" tap, for instance, does nothing). That's intentional: the design bundle's job is the visual/behavioral spec per screen, while actual screen-to-screen navigation is what the Flutter app itself demonstrates.
- The color palette (see below) is a first draft the user is still iterating on — confirm current values are still wanted before hardcoding them into a design-token file.

## Screens / Views
All four are 390×844 phone frames with `overflow-y: auto` (the frame is the viewport; content scrolls inside it like a real screen).

### 1. Login / Home (`Main.dc.html`)
- **Purpose:** Entry point for both personas — mechanic/workshop staff and vehicle owners — via a role toggle.
- **Layout:** Centered column, `padding: 32px 20px`, vertical stack `gap: 24px`: wordmark block → role segmented-control → card.
  - Wordmark: `Mototeca`, 26px/700/-0.025em, centered. Subtitle below, 14px, muted-gray.
  - Segmented control: two full-width buttons, `44px` tall, `border-radius: 8px` container. Active tab: petrol-blue background (`#1B4965`), white text. Inactive: white background, graphite text.
  - Card: `1px solid #E2E8F0`, white background, `border-radius: 10px`, subtle shadow.
- **Fields (role = oficina):** CNPJ da oficina (text), Senha (password). **Fields (role = proprietário):** Celular (text), Código recebido por WhatsApp (OTP text) — reflects the WhatsApp-first OTP auth described in `ARCHITECTURE.md` §6.
  - Inputs: `height: 44px`, `border-radius: 8px`, `1px solid #E2E8F0`, `font-size: 16px` (16px, not 14px, so mobile Safari/Chrome don't auto-zoom on focus).
- **Submit button:** full width, `height: 48px`, petrol-blue fill, white text, `border-radius: 8px`. Label: "Entrar" (visual only in this mockup — no cross-screen routing, see Fidelity above).
- **Below the form:** centered link "Não tem conta? Cadastre sua oficina".
- **Footer note** below the card (12px, muted): clarifies that looking up a bike's history does NOT require an account — only claiming ownership does.
- **Behavior:** role toggle swaps the fields shown, live in this mockup.

### 2. Mechanic Dashboard (`Dashboard.dc.html`)
- **Purpose:** Daily home base for workshop staff — the doc's "high-frequency, data-entry" persona.
- **Layout:** Sticky app bar (`#EAF3FA` background, `#CFE4F2` border) — wordmark + "Sair" button on row one, "Bem-vindo, {shopName}" on row two. Content stacks single-column, `padding: 20px`, `gap: 20px` — this replaces the old desktop 3-column card grid entirely:
  1. A slim stat banner ("Serviços registrados este mês" + count) instead of a standalone stat card.
  2. "Buscar Veículo" card (plate input + Buscar button).
  3. "Novo Registro" card, petrol-blue filled, full-width "Criar Registro" button.
  4. "Registros Recentes" — a vertical list of compact row cards: plate (mono) + vehicle label, operation types, date + km, mechanic name as a rounded pill badge.
- **Important scoping rule:** this list only shows service records created by the *logged-in* workshop (append-only, cross-shop-private) — it is NOT the full cross-workshop history of a vehicle. That full history only surfaces once a specific vehicle is looked up (see screen 3) or via the Customer Portal (screen 4). This distinction — "my shop's activity feed" vs. "one vehicle's full trusted history" — is core to the product's trust model per `ARCHITECTURE.md` §3.3/§4 and must be preserved in the real implementation.

### 3. New Service Record (`NewRecord.dc.html`)
- **Purpose:** The core data-entry action — log one maintenance visit against a vehicle.
- **Layout:** Sticky app bar with a back-chevron icon button + "Novo Registro" title (no more text-link back nav). Content stacks single-column, `padding: 18px 20px`.
  - **Vehicle card:** plate search input (mono, uppercase) + Buscar button, inline. Three states: not yet searched (empty), not found (yellow-tinted inline notice: "Veículo não encontrado... um novo cadastro será criado ao salvar"), found (slate-gray info panel showing make/model/year, plate, owner name, last recorded km).
  - **Operação Realizada card** (only rendered once a search has resolved): wrapping pill/chip toggles, one per item in the fixed 12-item operation taxonomy (`ARCHITECTURE.md` §3.2). Multi-select — selected = petrol-blue fill + white text, unselected = Azul-50 tint + rust-orange text.
  - **Detalhes card:** 2-col grid — Km atual, Valor (R$). "Peças utilizadas": each part is now a **stacked mobile row** (name full-width, then qty/cost/remove in a 3-column row) — the old 4-column desktop grid (`2fr 80px 120px 40px`) doesn't fit a 350px content width. "+ Adicionar peça" button. Observações (textarea, 3 rows). Fotos antes/depois: 2 image-upload slots side by side, 120px tall.
  - **Footer actions:** full-width stacked buttons — "Salvar Registro" (petrol-blue fill, primary) above "Cancelar" (outline) — not the old right-aligned side-by-side desktop pair.
- **Behavior:** plate search, chip multi-select, and add/remove part rows are live in this mockup; Salvar/Cancelar are visual only (see Fidelity above).

### 4. Customer Portal (`CustomerPortal.dc.html`)
- **Purpose:** Read-only, no-login-required lookup of a bike's full cross-workshop history — the "Carfax for motorcycles" surface. Distinct visual register from the mechanic screens: simpler header (no auth chrome), plate search is the sole entry action.
- **Layout:** Header: wordmark + one-line description, no user/logout chrome (matches the "no account needed to view" rule in `ARCHITECTURE.md` §3.4).
  - Search row: plate input (flex-grow, mono/uppercase) + "Consultar" button, `height: 44px`.
  - Not-found state: centered muted message in a bordered box.
  - Found state: vehicle summary card (make/model/year, plate in mono, color, current km) with a full-width "Baixar PDF" outline button **below** the info block — the old side-by-side desktop layout got cramped once the vehicle label could wrap to two lines at 350px.
  - "Histórico de Serviços" — a vertical stack of cards, one per past service, newest first: operation types (bold) + date at top, workshop name + mechanic + km (muted line), notes paragraph below.
  - Footer note (muted, 12px) reiterating no-account-needed, matching the login screen's footer note.

## Design Tokens

### Colors
Two accent colors on a shared neutral/slate scale (the neutral scale is intentionally reused from the "GoDE" reference design system this project inherited its base chrome from — see `Mototeca Brand.dc.html` for the full rationale/swatches):

| Role | Value | Notes |
|---|---|---|
| Primary (brand) | `#1B4965` (petrol blue) | Buttons, active nav/tab state, selected chips. HSL ≈ 203° 58% 25%. Passes ~9.6:1 contrast with white text. |
| Primary hover/pressed | `#2D7AA9` (Azul 500) | Hover/pressed state of a petrol-blue filled button — same hue/sat, lighter L. ~4.7:1 with white text. |
| Primary tint (bg only) | `#EAF3FA` / `#CFE4F2` (Azul 50 / 100) | Subtle tinted backgrounds/badges only — pair with graphite or Azul 700 text, never white text. |
| Primary structural | `#7EB8DD` (Azul 300) | Borders/dividers in the brand color only — never text or fill (fails contrast both directions). |
| Accent | `#B84F20` (rust orange) | Links, badge/mechanic-name text, chip text-on-tint. HSL ≈ 19° 70% 42%, ~5:1 contrast on white — this is the darker, text-safe variant. |
| Accent bright | `#D9622B` | Only used on dark (graphite) backgrounds — e.g. reversed logo lockup, app-icon mark — where it stays legible; do **not** use as a text color on a light/white background (only ~3.7:1 contrast there, fails AA for body text). |
| Graphite (text/dark surfaces) | `#0F172A` | Body text, headings, dark card/lockup backgrounds. Shared 1:1 with the inherited neutral scale. |
| Slate 50 / 100 / 200 / 500 | `#F8FAFC` / `#F1F5F9` / `#E2E8F0` / `#64748B` | Backgrounds, card/input borders, muted text — see `Mototeca Brand.dc.html` for full neutral scale. |
| Success / Warning / Destructive | `#22C55E` / `#EAB308` / `#EF4444` | Standard semantic colors, reused as-is. |

**Usage rules for the two accent scales** (full detail + swatches in `Mototeca Brand.dc.html`):
- Only the **700/base** step of either scale (`#1B4965` / `#B84F20`) may carry white text on top, or be used as button fills / link text directly on white. No other step in either scale has sufficient contrast for that.
- **50/100** tints are backgrounds only — always paired with graphite or the matching 700 text color, never white text.
- **300** is structural only — borders and dividers in the brand hue, never text or a button fill.
- **500** is the hover/pressed tone for a *filled* petrol-blue button. The orange scale has no filled-button role today (it's text/accent only) — if a filled-orange element is added later, treat 700 as its resting/selected state and 500 as its hover, mirroring the blue scale.
- **Complementary pairing rule:** blue and orange are a true complementary pair (~180–184° apart on the hue wheel). Only let them touch directly at the 700 grade (e.g. a petrol-blue button next to a rust-orange link) or with a neutral between them. Never place two matching mid-saturation/mid-lightness steps of the two scales directly adjacent (e.g. Azul 500 touching Laranja 500) — same-intensity complementary colors optically vibrate against each other.

### Typography
Inherited from the base reference design system, unchanged: **Inter** (400/500/600/700) for UI text, **JetBrains Mono** for plates, IDs, and monetary/numeric values. Sizes in use on the mobile screens: 26px/700 (wordmark), 22px/600 (login card title), 16–19px/600–700 (headers, section headings), 16px (form inputs, deliberately not 14px — see "About the Design Files"), 13–14px (body/labels/buttons), 11–12px (metadata/captions).

### Spacing & radii
4px base unit (Tailwind-style scale). Card/button/input radius: 8–10px (slightly larger than the old desktop draft's 6–8px — reads better as touch-sized mobile chrome). Card border: `1px solid #E2E8F0`. Card shadow: `0 1px 2px 0 rgb(0 0 0 / 0.05)` — very subtle, no other elevation is used anywhere. Every tappable control is **44px+ tall**.

## Interactions & Behavior implemented in each mockup
- Login: role toggle (oficina/proprietário) swaps the form fields shown; field inputs are bound.
- Dashboard: plate input is bound (no navigation on submit — see Fidelity above).
- New Service Record: plate search against 3 hardcoded vehicles shows the found-vehicle panel or a not-found notice; operation taxonomy chips are multi-select toggles; parts list supports add/remove rows.
- Customer Portal: plate search looks up the same 3 hardcoded vehicles and renders their (reverse-chronological) service history, or a not-found state.
- None of the above call a real backend, and none navigate to another screen — everything is in-memory mock state local to each artboard (artboards don't share state or logic with each other).

## State Management (for the real implementation)
Minimum state/data needs implied by these screens:
- Auth/session (role: oficina vs. proprietário; current workshop or owner identity).
- Vehicle lookup by plate (shared, cross-workshop read; per `ARCHITECTURE.md`'s `Vehicle`/`ServiceRecord` data model in §4).
- Service record draft state while filling the New Service Record form (multi-select ops, dynamic parts array, photo attachments) — `ARCHITECTURE.md` §9 calls out that this draft should tolerate connection drops via local persistence; not yet implemented in this prototype.
- Dashboard "this shop's recent records" query, scoped to the logged-in workshop only (distinct from the full per-vehicle history query used in screens 3 and 4).

## Assets
No photos/illustrations — the only custom visual asset is the logo mark (SVG, described/embedded directly in `Mototeca Brand.dc.html`: a circle "wheel" rim with a hub + two spokes, in petrol-blue/orange). The New Service Record screen's photo-upload icon and the part-removal icon are small inline stroke SVGs (16px). The Flutter app should adopt Material Icons (or whatever icon set fits) rather than trying to match these exactly.

## Files in this bundle
- `Main.dc.html` — Login/Home screen (entry point for both personas).
- `Dashboard.dc.html` — Mechanic Dashboard screen.
- `NewRecord.dc.html` — New Service Record screen.
- `CustomerPortal.dc.html` — Customer Portal screen.
- `canvas.json` — lays the four screens out side by side, phone-frame sized.
- `Mototeca Brand.dc.html` — color palette (full swatches + tonal scales + usage rules) and logo lockups (light/dark/app-icon versions). Not itself a screen, so it wasn't reshaped for mobile.
- `ARCHITECTURE.md` — the original product/technical architecture doc this design was built from (personas, data model, backend/mobile stack rationale, security/LGPD notes, phasing). Read this for any product decision not covered above.

The published canvas (link above) is the easiest way to view all four screens together, in-browser, without a build step; the `.dc.html` files here are the source of truth kept in version control.
