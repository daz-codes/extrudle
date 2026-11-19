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
- Product specs are versioned by being immutable once used (on any order line): editing a used spec creates the next revision via `ProductSpec::Revision`, copies its line rates and deactivates the old one. Orders keep the revision they were placed with. Toggling `active` alone never creates a revision.
- Sales orders: `SO-00001` numbering, one customer, required date per order, lines of spec + quantity (entered in kg or t, stored as grams). Status `open → scheduled → in_production → dispatched → invoiced`, plus `cancelled`. Only `open`/`scheduled` orders can be edited.
- Planner: change a line's plan only through `Schedule::Editor`, never by saving `ScheduleBlock`s directly. It reflows the line (`Schedule::Reflow`) and keeps order statuses right. Unlocked blocks run back to back from the line's start in queue order. Locked blocks never move, and jobs aren't split around them. Job durations are always `Schedule.job_minutes(planned_g, kg_per_hour)`, rounded up to 30-minute slots, using integer maths only. The queue start is stored in `lines.queue_starts_at` and only changes when the planner sets it. Changeovers marked `automatic` are rebuilt by the editor after every edit (one before each job whose spec differs from the previous job); changeovers the planner adds are kept and count as the changeover there. Jobs for orders still to make (open, scheduled or in production) can be planned; a started job (one with a production log) can be resized or re-timed but not moved in the queue or removed.
- Planner UI: `PlannerBoard` (controller concern) loads the board for a line and week. `ScheduleBlocksController` answers Turbo requests by replacing `#planner_board` and updating `#flash`. `Schedule::Timeline` slices blocks into UK-day rows of 30-minute slots for the CSS grid.
- Purchasing: `PO-00001` numbering (`SequentialNumber` concern, shared with sales orders). Status `draft → sent → part_received → received`, plus `cancelled`. Only drafts are editable; `back_to_draft!` reopens a sent PO for changes. The currency is set per PO (from the supplier) and fixed once it has lines. Prices are per tonne in minor units; `PurchaseOrderLine#total_cents` rounds each line half up to the penny with integer maths, and the PO total is the sum of the line totals.
- PDFs are Prawn classes in `app/pdfs` (e.g. `PurchaseOrderPdf`), using built-in Helvetica (Windows-1252; other characters are transliterated). Our company details come from `config/company.yml` via `Company`.
- Stock: change stock only through `Stock::Receipt` (goods in, with or without a PO line), `Stock::Transfer` (moves whole lots, a 0 g movement with from/to locations) and `Stock::Adjustment` (counted weight and a reason). Never update a lot's location or write `StockMovement`s directly; movements are read-only once saved. `Lot.with_quantity` adds the current weight in one query, and `Lot.in_stock` leaves out used-up lots. `Stock::OnHand` builds the stock report. Goods in sets the PO to `part_received`/`received` (`PurchaseOrder#refresh_receipt_status!`); `close_short!` accepts a short delivery.
- `Allocation.largest_remainder(total, weights)` / `Allocation.evenly(total, parts)` split integer grams exactly. Use them for any split (bags at goods in, consumption in Slice 7c).
- Lot labels are an HTML print page (`lots#labels`, A4 portrait sheets of 8, QR codes from rqrcode as inline SVG). The QR holds only the lot code.
- Production logs: `ProductionRun` is one log (form 5.4.1.2), started with `ProductionRun::Start` from a job block. It gets the next despatch number (editable), keeps the order line and spec revision, and puts the order `in_production`. One running log per line and one log per job. Record checks with `ProductionRun#record_check` (yes/no) and `#record_measurement` (width/thickness, judged against `ProductionRun::Checklist.range` and stored with the target and tolerance used). `ProductionRun::Board` gives each line's running log or next job. Log pages use `FloorOrOfficeLayout`, so floor users get the floor layout.
- Unanswered questions for Stu live in PLAN.md §11 with the working assumption the code uses. When building on an assumption, reference its Q number in a comment.
- Paper forms being replaced: 5.4.1.1 Extrusion Production Plan (an ordered queue per machine) and 5.4.1.2 Production Log (one per despatch number: header, material loads by reel range, reel-by-reel weights, QA checks). Screen and PDF layouts should stay recognisable to operators.
- Thickness is stored in microns as an integer (the paper plan writes 250µm as ".250").
- Material feeds per run: virgin_coex, virgin_mainex, pcw, regrind. Regrind is produced in-house.

## Design: "Lemon and Lime"
Clean and modern: zinc greys on a light grey canvas, with two fluorescent highlights. Style everything with Tailwind utilities plus the semantic classes in `app/assets/tailwind/application.css`. Don't put raw hex in views.

| Token | Role |
|---|---|
| `canvas` / `surface` | Page background (`#f4f4f5`) / cards and header (white) |
| `ink-50..950` | Zinc neutrals for text, borders and quiet fills. Body text is `ink-800`, headings `ink-900` |
| `lime-*` | Primary highlight (`lime-300 #d4f53c`): title underlines, current tab, `btn-accent`, selected choices, input focus, the wordmark |
| `lemon-*` | Secondary highlight (`lemon-300 #f5ff70`): link underlines, table row hover, warnings ("No rates"), notices |
| `ok` / `bad` | QA pass/fail, target vs actual (emerald / red) |

- Fonts: **Geist** for text and headings, **Geist Mono** for numbers in tables, table headers, eyebrows and units. Both are self-hosted in `app/assets/fonts` (no external font requests: floor terminals may be offline).
- Use `tabular-nums` for every weight, quantity and time, in tables, cards and `/floor/*` pages alike.
- Check contrast (WCAG AA, 4.5:1 for body text) for all text. On white, `ink-500` is the lightest grey for readable text; `ink-400` is for placeholders and decoration only.
- Highlights are for emphasis, not decoration. Text on lime or lemon is always `ink-900`, never white. Errors are always `bad`, never lemon.
- Headings: `.page-title` (fat lime underline) and `.section-title` / `.section-title-lg` (slimmer lime underline). Small caps labels use `.eyebrow`.
- Primary actions are `btn-primary` (ink). Use `btn-accent` (lime) for one standout action per page, and `btn-secondary` for the rest.
- Touch targets (buttons, tabs, nav links, choices) are at least 48px tall (`min-h-12`), and every interactive style that changes on `:hover` also changes on `:active`, since touch screens never hover.
- Office pages: dense but readable tables (`.data-table`). `/floor/*` pages: large type (≥ 20px body), big targets, high contrast.
- Light theme only for MVP.

Semantic classes: `.btn` (+ `-primary`, `-secondary`, `-accent`, `-danger`), `.card`, `.data-table`, `.badge` (+ `-quiet`, `-lime`, `-lemon`), `.link`, `.nav-link`, `.tabs`/`.tab`, `.choice`, `.field-label`, `.field-input`, `.field-hint`, `.field-group` + `.field-suffix`, `.eyebrow`. Layouts: `application` (office), `floor` (large type) and `auth` (sign-in pages).

Forms use `ExtrudleFormBuilder` (the default builder): `text_row`, `number_row`, `email_row`, `telephone_row`, `text_area_row`, `select_row`, `radio_row` (big tappable options for enums), `check_row` and `error_summary`. Each row renders the label, hint and inline errors. Use `suffix: "kg"` for units.

## Reusable model pieces
- `EnteredQuantity`: `quantity` typed in kg or t over `quantity_g` + `quantity_unit` (sales and purchase order lines).
- `SequentialNumber`: `numbered_with "PO"` gives `next_number` and `save_with_number`.
- `ScaledAttributes`: `scaled_attribute :max_reel_kg, column: :max_reel_g, scale: 1_000` gives forms a kg (or %) attribute over an integer column. Invalid input becomes a validation error.
- `Deactivatable`: `active` and `including_inactive(bool)` scopes. Master data is deactivated, never deleted.
- `MasterData` controller concern: office/admin only, plus `search_query` and `include_inactive?` for index filters.

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
