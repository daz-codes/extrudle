# CLAUDE.md — Extrudle

## What this is
Extrudle is a small ERP for a plastic sheet/film extrusion plant that runs recycled and virgin polymers. Two extrusion lines run 24/7. ~12 customers, ~40 product specs, ~15 suppliers. Single site, one company, ~5–20 users. Touch screens on the plant floor.

Full plan and phases: `PLAN.md` (in the repo root, next to this file). Work through it one slice at a time.

## Stack (keep it boring)
- Rails 8.1, Ruby 3.4 (see `.ruby-version`), **SQLite** (WAL mode; separate SQLite files for the app, Solid Queue, Solid Cache and Solid Cable)
- Hotwire (Turbo + Stimulus), importmap, Tailwind CSS (v4, via tailwindcss-rails)
- Rails 8 built-in authentication generator (`bin/rails generate authentication`)
- Solid Queue / Solid Cache / Solid Cable
- Minitest + fixtures, system tests with Capybara
- PDFs: Prawn (prawn, prawn-table)
- QR codes: rqrcode
- Deploy: Kamal to a single VPS or on-site box. The database lives on a persistent volume mounted at `storage/`
- Backups: Litestream streaming continuously to Cloudflare R2
- No SPA, no React. No extra gems without a clear reason.

## Domain rules (important)
- **No decimals or floats in the database.** SQLite has no true decimal type, so quantities are integers in their smallest unit:
  - Weights are **integer grams**, in columns named `*_g` (e.g. `quantity_g`, `weight_g`). Display kg or tonnes where useful.
  - Money is **integer minor units** (pence/cents), in columns named `*_cents`, plus a currency string (GBP, EUR, USD). No exchange-rate maths in MVP.
  - Percentages are **integer basis points**, in columns named `*_bp` (10000 = 100%).
  - Line rates are integer `kg_per_hour`.
- Parse user input with BigDecimal, never Float, then convert to integers. Use the `Weight` / `Money` helpers to format and parse; don't scatter `/ 1000` around views.
- Allocations that split a total (e.g. material consumption across bags) must add up exactly. Use the largest-remainder method for the leftover grams.
- Times are stored in UTC and displayed in Europe/London. The planner has 48 × 30‑minute slots per day, and schedule blocks snap to 30 minutes.
- Stock is tracked as lots (a bag/octabin/batch). Stock levels are computed from lot movements and never edited directly.
- Every stock change is a StockMovement row (receipt, transfer, issue_to_production, adjustment). Lot quantity = sum of movements.
- A lot has a location: on_site, storage, at_supplier, in_transit.
- The capping‑layer polymer is shared by both lines. Consumption is allocated per production run (see PLAN.md §4).
- Product specs are versioned by being immutable once used: editing a used spec creates a new revision.
- Paper forms being replaced: 5.4.1.1 Extrusion Production Plan (an ordered queue per machine) and 5.4.1.2 Production Log (one per despatch number: header, material loads by reel range, reel-by-reel weights, QA checks). Screen and PDF layouts should stay recognisable to operators.
- Thickness is stored in microns as an integer (the paper plan writes 250µm as ".250").
- Material feeds per run: virgin_coex, virgin_mainex, pcw, regrind. Regrind is produced in-house.

## Design
Professional and calm: **greys and blues, with orange/ginger highlights**. Style everything with Tailwind utilities, and only extract components (partials, or `@apply` sparingly) when markup repeats.

Define semantic colour tokens once in `app/assets/tailwind/application.css` with `@theme`, and use those names in views, not raw hex:

| Token | Role | Base |
|---|---|---|
| `ink` (slate scale) | Text, borders, surfaces, tables | Tailwind `slate` |
| `brand` (blue scale) | Nav bar, primary buttons, links, selected state | deep steel blue, e.g. `brand-700 #1E4E8C`, `brand-900 #0F2A4D` |
| `ginger` (orange scale) | Highlights: urgent orders, the planner's "now" line, the active reel row, focus rings, key figures | e.g. `ginger-500 #E07B2E`, `ginger-600 #C4621C` |
| `ok` / `bad` | QA pass/fail, target vs actual | Tailwind `emerald` / `red` |

- Use ginger sparingly, like the highlighter pen on the paper plan. If everything is orange, nothing stands out. It is never the colour for errors (that's `bad`).
- The page background is `slate-50` with white cards. The nav is `brand-900` with white text.
- Body text is `slate-800` on white. Check contrast (WCAG AA) for all text, including white text on ginger buttons (use `ginger-700` or darker; `ginger-600` fails AA for body text).
- Typography: system font stack, tabular numbers (`tabular-nums`) for every weight, quantity and time column.
- Office pages: dense but readable tables. `/floor/*` pages: large type (≥ 20px body), big targets, high contrast.
- Light theme only for MVP.

Shared building blocks live in `application.css` under `@layer components`: `.btn` (+ `.btn-primary`, `.btn-secondary`, `.btn-accent`, `.btn-danger`), `.field-label`, `.field-input`, `.field-hint`, `.card`, `.badge`. Layouts: `application` (office), `floor` (large type) and `auth` (sign-in pages).

## Roles
`User#role` is `admin`, `office` or `floor`. Use `require_role :admin, :office` in controllers (`Authorization` concern). Floor users only see `/floor` and are redirected there from office pages. Deactivated users can't sign in.

## Conventions
- RESTful controllers, thin. Business logic in plain Ruby objects in app/models (e.g. `Schedule::Reflow`, `Stock::Receive`).
- Enums as Rails string-backed enums.
- Every model change ships with a test. Run `bin/rails test` and `bin/rails test:system` before saying a task is done.
- In system tests, sign in with the `sign_in` helper and call `wait_for_turbo` before clicking straight after a Turbo navigation.
- Touch-first UI: buttons ≥ 48px tall, no hover-only interactions, large type on `/floor/*` pages.
- Keep `db/seeds.rb` realistic (2 lines, 12 customers, ~10 specs, 5 material categories, suppliers, some POs and lots) so screens can be demoed.

## How to work
- Do one slice from PLAN.md per session. Plan first, then build, then test.
- Ask before adding a gem, changing the schema of an existing table with data, or changing the domain rules above.
- Update the checklist in PLAN.md when a slice is done.
