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
- Backups: Litestream streaming continuously to Cloudflare R2 (see `docs/backups.md`)
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
- Draft plans (Slice 7e): one `PlanDraft` at a time holds a copy of every line's blocks (`schedule_blocks.plan_draft_id`; each copy keeps `source_block_id`) and queue starts (`PlanDraftLine`). `Schedule::Plan` is the live plan or a draft: pass it to `Schedule::Editor.new(line, plan:)`, `Schedule::Warnings.for_line(…, plan:)` and use it for planned/unplanned weight while drafting. `Line#schedule_blocks`, `SalesOrderLine#schedule_blocks` and `ScheduleBlock.live` are live only, so anything the floor, order statuses or production logs read must use those. Only live edits refresh order statuses. While a draft exists the planner can't edit the live plan (`ScheduleBlocksController`); new blocks go into the draft. `Schedule::Publish` updates live blocks in place from their draft copies (production logs stay attached), adds new ones, removes dropped ones (never a started job), reflows and refreshes statuses in one transaction. A draft block counts as started when its live job has (`ScheduleBlock#started_run`).
- Job colours: every customer has a `colour` (lime unless chosen; lemon and lime are ordinary choices) and `schedule_blocks.colour` (jobs only, nil = the customer's) overrides it; `JobColour.for(block)` picks. Names are `JobColour::NAMES`; colour a bar with `JobColour.css_class`. Change a block's colour through `Schedule::Editor#update(colour:)`, so drafts and publish carry it. Urgent jobs are marked by a black double border (`PlannerHelper#urgent_border`, `.timeline-urgent`; Q73), never by a colour option.
- Optimise (Slice 11): `Schedule::Optimise.new(draft.plan).call` replans both lines around required dates, into a draft only (`PlanOptimisationsController` starts one if needed). It moves only jobs not started for active orders (to the other line only with a rate there), adds jobs for unplanned order lines, keeps urgent jobs first, keeps locked blocks, started jobs and other blocks in place (but "no orders" goes after the last job), and writes each line through `Schedule::Editor#rearrange`. Score in order: late orders, minutes late, changeovers, finish times (Q76); ties random.
- Planner UI: `PlannerBoard` (controller concern) loads the board for a line and week. Drag and drop (Slice 10, `planner_drag_controller.js`, pointer events, no library) only sends `PATCH …/drop` with the new start: a queued block goes through `Schedule::Editor#move_to_time` (a queue place, never pinned; Q74), a locked block through `#lock(starts_at:)` (Q75). `PlannerHelper#draggable_block?` decides what can be dragged; keep the ▲ ▼ buttons for keyboards. `ScheduleBlocksController` answers Turbo requests by replacing `#planner_board` and updating `#flash`. `Schedule::Timeline` slices blocks into UK-day rows of 30-minute slots for the CSS grid.
- Purchasing: `PO-00001` numbering (`SequentialNumber` concern, shared with sales orders). Status `draft → sent → part_received → received`, plus `cancelled`. Only drafts are editable; `back_to_draft!` reopens a sent PO for changes. The currency is set per PO (from the supplier) and fixed once it has lines. Prices are per tonne in minor units; `PurchaseOrderLine#total_cents` rounds each line half up to the penny with integer maths, and the PO total is the sum of the line totals.
- PDFs are Prawn classes in `app/pdfs` (`PurchaseOrderPdf`, `ProductionLogPdf`), using built-in Helvetica (Windows-1252; other characters are transliterated). Shared colours and formatting (`text`, `quantity`, `kg_number`, `date`, `date_time`) are in `PdfFormatting`. `ProductionLogPdf` prints a log like form 5.4.1.2 (`production_runs#show` as `.pdf`), using the same view helpers as the screens via `ApplicationController.helpers`. Our company details come from `config/company.yml` via `Company`.
- Stock: change stock only through `Stock::Receipt` (goods in, with or without a PO line), `Stock::Transfer` (moves whole lots, a 0 g movement with from/to locations) and `Stock::Adjustment` (counted weight and a reason), plus production's own: `ProductionRun#finish!` (issues) and `Stock::Reconciliation` (empty bags). Never update a lot's location or write `StockMovement`s directly; movements are read-only once saved. `Lot.with_quantity` adds the current weight in one query, and `Lot.in_stock` leaves out used-up lots. `Stock::OnHand` builds the stock report. Goods in sets the PO to `part_received`/`received` (`PurchaseOrder#refresh_receipt_status!`); `close_short!` accepts a short delivery.
- Goods in on the floor (Slice 12): `Floor::DeliveriesController` (`/floor/deliveries`) lists sent and part-received POs and shows one with today's bags and **Print labels**. Floor users receive through the same `GoodsReceiptsController` (`FloorOrOfficeLayout`, back to the floor page) and can open `lots#labels`; the rest of Stock and Purchasing stays office only. Never show floor users prices or incoterms (Q82).
- `Allocation.largest_remainder(total, weights)` / `Allocation.evenly(total, parts)` split integer grams exactly. Use them for any split (bags at goods in, consumption in Slice 7c).
- Lot labels are an HTML print page (`lots#labels`, A4 portrait sheets of 8, QR codes from rqrcode as inline SVG). The QR holds only the lot code.
- Production logs: `ProductionRun` is one log (form 5.4.1.2), started with `ProductionRun::Start` from a job block. It gets the next despatch number (editable), keeps the order line and spec revision, and puts the order `in_production`. One running log per line and one log per job. Record checks with `ProductionRun#record_check` (yes/no) and `#record_measurement` (width/thickness, judged against `ProductionRun::Checklist.range` and stored with the target and tolerance used). `ProductionRun::Board` gives each line's running log or next job. Log pages use `FloorOrOfficeLayout`, so floor users get the floor layout. The log has four tabs: Log (`production_runs#show`), Materials (`material_loads#index`), Reels (`reels#index`, Turbo Stream replaces `#reels_panel`) and End of run (`run_finishes#show`). Reels are numbered per run and the run total is the sum of its reels (never stored); build the entry form's reel with `ProductionRun#build_next_reel` (by id, so it stays out of the totals). `ProductionRun#finish!` checks `finish_problems` (reels, bags loaded, end readings, line clearance, a comment if out of tolerance); finished logs can't change.
- Materials (Slice 7c): `MaterialLoad` is a bag (lot) going on a feed (`MaterialLoad::FEEDS`) of a log from a reel number; it feeds until the next bag on that feed. Add loads only with `ProductionRun::LoadMaterial` (finds the lot by code, picks the usual feed from the material, marks the replaced bag empty unless told not to, moves a bag from storage on site, and keeps a bag on one feed of one line except the shared Co-Ex feed). `ProductionRun#current_loads` / `#reel_range(load)` give the log view. Recipes are `SpecIngredient` rows per feed (basis points, adding up to 10000), edited with `ProductSpec::Recipe` like line rates (no new revision, copied to revisions and duplicates); specs without one use `ProductSpec::Recipe::STANDARD_BP`. `ProductionRun::MaterialUse` allocates output → feeds by recipe → bags by the reel weight each fed, with `Allocation.largest_remainder`; `finish!` posts it as `issue_to_production` movements with `production_run_id` (`ProductionRun#consumptions`). Bags are marked empty with `Stock::Reconciliation.mark_empty`, only if they have been on a line (anything else is a `Stock::Adjustment`); once no running log used the bag, its leftover book weight is posted as an adjustment flagged `bag_variance` (the variance; find it by the flag, never the note) and `lots.reconciled_at` is set. Take a mistaken load off with `MaterialLoad#remove!`, which un-marks the bag it marked empty (`marked_previous_empty`). Carry-over skips bags marked empty, off site, or on the other line's running log (`MaterialLoad.feeding_elsewhere`). `Stock::Variance` is the report at `/stock/variance`.
- Dispatch (Slice 8): a `Pallet` is worked out from a log's reels and pallet numbers (`ProductionRun#pallets`, label `731/2`), never stored. `DeliveryNote` (`DN-00001`, `draft → dispatched`, back to draft with `undo_dispatch!` until exported) holds pallets as `DeliveryNotePallet` rows (unique per run and pallet number: a pallet goes out once). Once a pallet is on a note its reels can't change weight, pallet or be removed, and the next reel goes on a new pallet. `SalesOrder#pallets_to_dispatch` lists complete pallets not yet on a note. `mark_dispatched!` calls `SalesOrder#refresh_dispatch_status!` (dispatched once every line has gone in full; `mark_dispatched!` on the order closes a short one). `SageExport.create_from!(SageExport.ready_notes)` writes the Sage 50 Audit Trail Transactions CSV (one SI row per spec per note, `config/sage.yml` for nominal and VAT rates), stores the file, marks notes exported and orders invoiced. CSV is read and written with Ruby's `csv` library (in the Gemfile, as it's a bundled gem since Ruby 3.4). `DeliveryNotePdf` prints the note.
- Go-live (Slice 9): spreadsheet imports are `Import::*` classes on `Import::Base` (declare `column`s with aliases; `import_row` returns `[label, action]`; `preview` runs in a rolled-back transaction, `save` is all or nothing, each row in a savepoint; blank cells never clear a field). `Import::CsvReader` wraps `CSV.parse` for Excel's quirks (byte order mark, Windows-1252, semicolon or tab separators). Opening stock warns (`warn_about_row`) when a batch is already in stock. Litestream runs only when `LITESTREAM_BUCKET` is set (`bin/docker-entrypoint`, `config/litestream.yml`); `Backup::RestoreCheck` restores the latest backup and checks it (nightly job, Users › Backups); `bin/backup-drill` proves a restore locally with Docker. Runbooks are in `docs/backups.md` and `docs/go-live.md`. The Help page (`help#show`) is the training notes: keep it in step with button names when screens change. `BlankProductionLogPdf` shares `LogLayout` with `ProductionLogPdf`.
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
| `pistachio`, `avocado`, `banana`, `mango`, `mandarin`, `cherry`, `raspberry`, `blackcurrant`, `blueberry`, `chocolate` | Planner job colours only, via `.job-colour-<name>` (with lime and lemon). Never use them elsewhere |

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
Only approved computers can use Extrudle when `Device.required?` (`REQUIRE_APPROVED_COMPUTERS`, on in production, off on the preview, in development and in test). `ApprovedComputers` (in `ApplicationController`) checks the device cookie on every request after sign-in; sign-in and password reset skip it (`allow_unapproved_computers`), and only `users.sign_in_anywhere` admins can sign in on an unapproved computer, then approve it under Users › Computers. Only a digest of each computer's token is stored. Tests switch it on with `Rails.configuration.x.require_approved_computers = true` (and restore it in teardown).
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
