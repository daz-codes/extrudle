# Build plan — Extrudle (Rails 8)

This file lives at the app root as `PLAN.md` (next to `CLAUDE.md`). Each **slice** is sized for one Claude Code session.
Tick boxes as you go.

---

## 1. Feasibility in short
Yes, this is very achievable. It is a classic small-manufacturing app: master data, a scheduler,
lot-tracked stock and paperwork. The only fiddly parts are:

1. **The planner UI** (drag/re-order blocks, auto-reflow of later jobs). Keep it simple: an ordered list per line that calculates times, plus a visual timeline. Drag-and-drop comes later.
2. **The shared capping polymer** — allocation between two lines (approach below).
3. **Sage** — which Sage matters (Sage 50 desktop vs Sage Business Cloud Accounting). Start with a CSV export; API later.

Scanners are easy to add later: USB/Bluetooth barcode scanners act as a keyboard, so a scan
is just text typed into a focused field. Design for that now and nothing needs rewriting.

### Storage decisions (SQLite)
- The database is **SQLite** (the Rails 8 default). The load is tiny: 5–20 users and two lines logging reels. The app, Solid Queue, Solid Cache and Solid Cable each get their own SQLite file in WAL mode.
- SQLite has no true decimal type, and `SUM()` runs in floating point. So **every quantity is an integer in its smallest unit**:
  - weights are **integer grams** (`*_g`). This is the same precision as decimal(12,3) kg, and every sum is exact.
  - money is **integer minor units** (`*_cents`, i.e. pence/cents) plus a currency string.
  - percentages are **integer basis points** (`*_bp`, so 10000 = 100%).
- Forms accept kg or tonnes. Input is parsed with BigDecimal (never Float), converted to grams, and shown as kg/t through a small `Weight` helper.
- Backups: Litestream streams the database continuously to Cloudflare R2, which gives point-in-time restore.

---

## 2. Core data model

```
Customer ─< SalesOrder ─< SalesOrderLine >─ ProductSpec
                                  │
                                  └─< ScheduleBlock (kind: job) >─ Line
Line ─< ScheduleBlock (kind: job | changeover | planned_maintenance | unplanned_maintenance | no_orders)

ProductSpec ─< SpecIngredient >─ Material        (recipe: share per layer, in basis points)
ProductSpec ─< LineRate >─ Line                   (kg/hour on that line)

Supplier ─< PurchaseOrder ─< PurchaseOrderLine >─ Material
PurchaseOrderLine ─< Lot ─< StockMovement
Material >─ MaterialCategory   (~5: virgin PE, recycled PE, capping polymer, additive/masterbatch, silicone…)

ScheduleBlock(job) ─< ProductionRun ─< RunConsumption >─ Lot
ProductionRun ─< FinishedReel >─ Pallet ─< DeliveryNoteLine >─ DeliveryNote >─ SalesOrder
```

### Key tables (MVP columns)
Field names below come from the current paperwork: form 5.4.1.1 Extrusion Production Plan and form 5.4.1.2 Production Log.

- **Line**: name (e.g. `D1`), machine_no, default_changeover_minutes
- **ProductSpec**: code, customer (optional), width_mm, thickness_micron (integer; the plan writes 250µm as ".250"), material_type (clear/laminated), pe (bool), silicone (none/underside/reverse/both), silicone_bp, antiblock (bool), core_inches (3/6), core_orientation (horizontal/vertical), reel_size (max_roll_on_side / max_diameter_mm, e.g. 600 or 1000), max_reel_g, pallet_type (euro/standard), reels_per_pallet, label_inside_core (bool), packaging_notes (text, e.g. "best-quality pallets", "least adhesive tape on core"), customer_part_no, customer_tool_no, customer_product_code, customer_description, revision, active
- **LineRate**: line, product_spec, kg_per_hour (integer)  ← drives block duration (the sample log is ~190 kg/h for 700mm × 250µm, but confirm)
- **SalesOrder**: customer, customer_po_ref (e.g. `M15159`, `P15745`), required_date, urgent (bool, e.g. "URGENT 19/08 dispatch"), status (open/scheduled/in_production/dispatched/invoiced)
- **SalesOrderLine**: product_spec, quantity_g, customer_batch_no (some customers send one, e.g. Charpak)
- **ScheduleBlock**: line, kind, position, starts_at, ends_at, sales_order_line (nullable), planned_g, notes, locked (bool)
- **Supplier**: name, country, default_currency, default_incoterm
- **Material**: name, category, supplier (optional), grade, virgin/recycled
- **PurchaseOrder**: supplier, number, currency, incoterm (EXW/FOB/CIF/DAP/DDP…), status, expected_date
- **PurchaseOrderLine**: material, quantity_g, price_per_tonne_cents
- **Lot**: material, po_line, supplier_lot_ref, code (our QR/label ID), location, received_on, initial_g
- **StockMovement**: lot, kind, quantity_g (+/-), production_run (nullable), user, note
- **ProductionRun** (= one Production Log, identified by its **despatch number**, e.g. 731): schedule_block, line, despatch_number, started_at, ended_at, antiblock_batch_no, silicone_batch_no, pe_film_batch_no, technician_days, technician_nights, special_instructions, comments_corrective_actions, total_g
- **MaterialLoad**: production_run, feed (`virgin_coex` / `virgin_mainex` / `pcw` / `regrind`), lot, from_reel_no, to_reel_no, operator, loaded_at. *The log records materials by **reel range**, not by time, e.g. "JADE bag 939, reels 1–5".*
- **Reel** (finished): production_run, reel_no, produced_at, weight_g, length_m, pallet, spec_check_initials. The running total is calculated, not stored.
- **Pallet**: production_run, pallet_no, weight_g (often one reel per pallet)
- **RunCheck**: production_run, stage (`prestart` / `startup` / `pallet` / `end_of_run` / `line_clearance`), item, target, actual, passed (Y/N), user, at. Prestart: previous documents and labels removed, previous product cleared from the line. End: width and thickness target vs actual. Clearance: materials cleared, log and documents removed, line cleared for the new micron.
- **RunConsumption**: production_run, lot, quantity_g, method (scanned/manual/allocated). Derived from MaterialLoads (see §4).
- **DeliveryNote**: sales_order, production_run(s), number, dispatched_on, haulier, exported_to_accounts_at. A run can have up to 3 deliveries ("Nº of deliveries" box on the log).
- **Regrind** is made in-house: edge trim and scrap get reground into lots with our own lot codes (e.g. "chip"). Treat it as a Material with `source: internal`.

---

## 3. Planner logic
- **Today's plan is a sequenced list per machine with no times** (6 pages for D1). The app should feel the same: an ordered queue per line, with calculated start/finish times added.
- The **printed view should copy the current form 5.4.1.1 columns**: Customer & Order No (with part/tool/product codes and required date), Quantity, Micron, Width, PE, Silicone, Antiblock, Reel Size, Additional Info & Packaging. Operators will trust it more if it looks familiar.
- Highlight urgent orders and orders that are late against their required date (on paper this is done with coloured highlighter).
- Each line has an ordered list of blocks. Times are **calculated**, not typed:
  `job duration = planned_g ÷ (LineRate.kg_per_hour × 1000)`, rounded **up** to 30 minutes (integer maths).
- After each job the planner suggests a changeover block (line default; later: a spec-to-spec changeover matrix).
- Maintenance and "no orders" blocks have a fixed duration.
- **Reflow**: when a block is inserted, moved, resized or deleted, all later unlocked blocks on that line shift. A `locked` block (e.g. booked engineer visit) never moves; reflow flows jobs around it.
- Warnings: job finishes after the order's required date; spec has no rate for that line.
- Views: (a) week timeline per line with 30-min grid (CSS grid, 48 columns per day), (b) a printable list that replaces the Word doc.

## 4. Material consumption and the shared capping polymer
The log already records material in four streams: **Virgin Co‑Ex** (probably the capping layer), **Virgin Main‑Ex**, **PCW** (flake) and **Regrind**. Each entry names a bag (supplier, batch, bag no., ~1,000–1,100 kg) and the reel range it fed. Bags span several reels and several runs, so we can't record exact kg per run. Instead:

1. **Load**: an operator records a bag going on a feed (`MaterialLoad`) together with the first reel number. That bag moves to the line's WIP/drier location.
2. **Allocate**: when the run ends, work out each stream's kg as run output × that stream's recipe % for the spec, split across the bags loaded on it in proportion to reel weights. This gives `RunConsumption` rows with method `allocated`. All of this is integer grams: hand out the rounding remainder with the largest-remainder method so the allocated rows add up exactly to the stream total.
3. **Shared Co‑Ex polymer**: it works the same way. One bag can show up in loads on both lines, so it is allocated to whichever runs used it, across both lines.
4. **Reconcile**: when a bag is marked empty, compare its received weight with the total allocated. Post the difference as an adjustment and show it on a variance report.

The result is full traceability from any reel to its supplier bags (and back), with no weighing beyond what happens today.

## 5. Hardware notes (Phase 2)
- **Touch screens**: any tablet/all-in-one running a browser in kiosk mode, pointed at `/floor`. Install as a PWA.
- **Scanners**: USB/Bluetooth HID 2D scanners (QR needs 2D). Rugged models for the plant.
- **Label printers**: Zebra (or similar) thermal printers on the network, printing ZPL sent from the server. Use 100×150mm labels for bags and pallets.
- **QR content**: just the lot code (e.g. `L-2026-000123`), not all the data. The app looks up the rest. Keeps codes short and labels reprintable.

---

## 6. MVP — Phase 1 (no scanners)
Goal: replace the Word production plan and give a live stock figure.

- [x] **Slice 0 – Setup**: `rails new --database=sqlite3 --css=tailwind`, auth generator, Tailwind theme tokens and layout with nav (see CLAUDE.md §Design), `Weight`/`Money` display helpers, roles (admin/office/floor), Kamal config with a persistent volume for `storage/`, CI running tests. Move `PLAN.md` and `CLAUDE.md` into the app root.
- [x] **Slice 1 – Master data**: Customers, Suppliers, MaterialCategories, Materials, Lines, ProductSpecs (with dropdowns for silicone/core/etc.), LineRates. CRUD screens + seeds. Spec "duplicate as new" button.
  - Deferred: `SpecIngredient` recipes (built in Slice 7c, per feed, with a guessed standard recipe, §11 Q6) and locking used specs into new revisions (Slice 2, once orders reference specs).
- [x] **Slice 2 – Sales orders**: orders with lines (spec dropdown pre-fills spec details read-only, quantity in kg/tonnes toggle), status, list filtered by required date.
  - Also: spec revision locking (edits to a spec on an order create the next revision). Statuses after `open` are only reachable by cancel/reopen until Slices 3–8 set them. Working assumptions Q11–Q14 are in §11.
- [x] **Slice 3 – Planner model**: `ScheduleBlock`, duration calc, `Schedule::Reflow` service, locked blocks, warnings. Heavy unit tests here.
  - Built as `ScheduleBlock`, `Schedule::Reflow`, `Schedule::Editor` (add/insert/move/resize/replan/lock/unlock/remove/start_at, automatic changeovers) and `Schedule::Warnings` (late, no rate, over-planned, idle before a locked block). Orders switch between open and scheduled automatically. Assumptions: §11 Q15–Q17.
- [x] **Slice 4 – Planner UI**: per-line week timeline (48 slots/day), add job from an unscheduled order line, add changeover/maintenance/no-orders blocks, move up/down buttons (Turbo Streams), print view.
  - `/planner`: a tab per line, week navigation, and a day × 48-slot CSS grid timeline (46/50 slots on clock-change days) with a now line. A queue list with ▲ ▼ / edit / remove (Turbo Streams), "Orders to plan" (most pressing first, estimated time on this line), and "Add a block" (kind, hours, position, optional fixed time). A block edit page covers weight, hours, lock and notes. `/planner/print` is laid out like form 5.4.1.1, landscape A4, with start/finish times and urgent/late rows marked. Drag-and-drop is still Phase 3.
- [x] **Slice 5 – Purchasing**: POs with currency, incoterms, lines in kg, price/tonne; PO PDF; status (draft/sent/part-received/received).
  - Also: draft → sent → back to draft to amend, cancel/reopen. `part_received`/`received` are set by goods in (Slice 6). Our company details for the PDF are placeholders in `config/company.yml`. Working assumptions Q18–Q24 are in §11.
- [x] **Slice 6 – Goods in & stock**: receive against a PO line → creates Lots + StockMovements; set location (on site/storage/at supplier/in transit); transfer between locations; stock-on-hand by material and category; printable lot labels (A4 sheet of QR codes is fine for MVP).
  - Also: goods in splits a delivery's total weight evenly across its bags (largest remainder), stock without a PO for opening stock and regrind, weight adjustments with a reason, "close short" for part-received POs, and stock still on order. Working assumptions Q25–Q32 are in §11.
- [x] **Slice 7a – Production log (header and checks)**: start a run from a schedule block. It gets a despatch number and pre-fills customer, order, spec, gauge, width and material type. Record additive batch nos, technicians and prestart checks. Width/thickness target vs actual is shown red/green.
  - Also: the log works for floor users in the floor layout, and the floor page shows each line's running log or next job. The home page cards link to their sections. Working assumptions Q33–Q39 are in §11.
- [x] **Slice 7b – Reel entry**: a fast touch-friendly grid replacing page 2 of the log, with reel no, time (auto), weight, length, pallet and initials. Show a running total and a "% of order" bar. End-of-run checks and line clearance follow.
  - Also: the log is split into Log / Reels / End of run tabs; reels are added with Turbo and the weight box refocuses; pallet and initials carry over; finishing needs reels, both end readings, full line clearance and a comment if an end reading is out of tolerance. Working assumptions Q40–Q44 are in §11.
- [x] **Slice 7c – Material loads and allocation**: record bags per feed against reel ranges, using a lot-code field that a scanner can fill later. Allocation and reconciliation as in §4. Stock deducts automatically.
  - Also: a Materials tab on the log (bags on each feed, "Bag empty", load by lot code with Enter), a recipe card on each spec (standard recipe until Stu gives real shares), bags carried over to the line's next log, finishing posts `issue_to_production` movements against the run, and "Bags on the lines and variance" under Stock. Working assumptions Q46–Q51 are in §11.
- [x] **Slice 7d – Printable log**: a PDF that looks like the current 5.4.1.2 form, for audits and ISO records.
  - Also: "Print log" on every tab of a log and a PDF link per log on the Production list. Page 1 is the header boxes, batches, prestart and start-up checks and the bags loaded (with kg used); the reel sheet starts on page 2, then end-of-run readings, line clearance, comments and sign-off lines. A running log prints marked "in progress". Working assumptions Q59–Q62 are in §11.
- [x] **Slice 7e – Draft plans**: the planner prepares a new plan for both lines as a draft, while the floor, the board's next job and order statuses keep using the live plan, unchanged. **Publish** replaces the live plan in one step; **Discard** throws the draft away. No approval step and no notice on the floor (Stu, 19 Nov 2026).
  - Model: one `PlanDraft` at a time (started by, started at) holding its own copy of every line's blocks (`schedule_blocks.plan_draft_id`, null = live) and each line's queue start. Each copied block keeps `source_block_id`, its live block. `Schedule::Editor` works on the live plan or on a draft; only live edits refresh order statuses. Every live read (floor board, next job, warnings, order statuses, unplanned weight, print) must use the live plan only.
  - Publish, in one transaction: copy the draft's changes onto the live blocks (so a started job keeps its production log), add new blocks, remove live blocks the draft dropped (never a started job), reflow both lines and refresh order statuses. Before publishing, show what changed in reality since the draft began (jobs started, orders cancelled or added) and what will happen to each.
  - Planner UI: "Start a new plan", a draft banner showing who started it and when, Publish / Discard, switch between the draft and the live plan, and print either. Working assumptions Q52–Q55 are in §11.
  - Built as `PlanDraft` (+ `PlanDraftLine` for queue starts), `Schedule::Plan` (live or draft, passed to `Schedule::Editor`, `Schedule::Warnings` and the board) and `Schedule::Publish` (changes per line, notes on what happened meanwhile, one-transaction publish). `Line#schedule_blocks`, `SalesOrderLine#schedule_blocks` and `ScheduleBlock.live` read the live plan only. Cancelling an order takes its jobs off the draft straight away, as well as the live plan.
- [x] **Slice 8 – Dispatch**: pallets from reels, delivery note PDF, mark order dispatched; **Sage CSV export** of dispatched-but-not-invoiced notes.
  - Built as: `Pallet` (worked out from a log's reels and pallet numbers), `DeliveryNote` (`DN-00001`, draft → dispatched, back to draft until exported) with `DeliveryNotePallet` (a pallet goes out once, and its reels are then fixed), `DeliveryNotePdf`, and `SageExport` (Sage 50 Audit Trail Transactions CSV, kept for re-download). Dispatching sets the order `dispatched` once every line has gone in full (or by hand for a short delivery); exporting sets it `invoiced` once all its notes have gone. Customers have a Sage account reference and VAT code. The log PDF's "No. of deliveries" box is filled in. Working assumptions Q63–Q68 are in §11.
- [x] **Slice 8a – Approved computers**: only computers an admin has approved can use Extrudle. Stu's admin account can sign in from any computer and approve the one it's on (Stu, 19 Nov 2026). IP addresses aren't used: every computer on the site shares one public address.
  - `Device`: name, token digest, approved by, last used at, last IP, active. Approving sets a long-lived signed, httponly, secure cookie holding a random token; only its digest is stored. Every request checks the device, not just sign-in, so revoking a computer signs it out at once.
  - `users.sign_in_anywhere` (admins only, set on Stu's account). Admin › Computers lists, renames and revokes them. An unapproved computer sees "This computer isn't approved for Extrudle. Ask an admin to approve it."; password reset still works there, but signing in doesn't.
  - Switched on by a setting, so the demo preview can stay open; on for the real deploy. Working assumptions Q56–Q58 are in §11.
  - Built as `Device` (token digest, approved by, last used and IP, browser, revoked at/by), the `ApprovedComputers` controller concern (runs on every request, after sign-in), `Admin::DevicesController` (Users › Computers) and `users.sign_in_anywhere`. The setting is `REQUIRE_APPROVED_COMPUTERS`: on by default in production, off on the preview (`config/deploy.yml`) and in development and test. The first production admin (`ADMIN_EMAIL`) and Stu's demo account get `sign_in_anywhere`. An admin can't untick their own "sign in anywhere" while on an unapproved computer.
- [x] **Slice 9 – Polish & go-live**: import real specs/customers/suppliers from spreadsheets (CSV importer), Litestream backups to R2 plus a tested restore, user training notes. Printable blank 5.4.1.2 logs as a paper fallback if the system is down.
  - Built as: Master data › Import (`Import::*`: suppliers, materials, customers, product specs with line rates, opening stock; templates, a checked preview, all or nothing; CSV read by `Import::CsvReader`), Litestream in the Docker image and entrypoint (real deploy only, `config/litestream.yml`), a nightly restore check (`Backup::RestoreCheck`, Users › Backups) and `bin/backup-drill` (a local restore drill with Docker), an in-app Help page by role, and `BlankProductionLogPdf` (Production › Blank paper log, also on the Floor page). Runbooks: `docs/backups.md` and `docs/go-live.md`. Working assumptions Q69–Q72 are in §11.
- [x] **Slice 10 – Drag and drop on the planner** (Stu, 24 Nov 2026; brought forward from Phase 3): drag a job along the week timeline to plan it. A drop **reorders** the queue and the line reflows, so the job runs as near the drop point as the queue allows; it doesn't pin the job at that exact time (Q74). The ▲ ▼ and Edit buttons stay, for precise changes and for keyboard users.
  - Model: `Schedule::Editor#move_to_time(block, time)`. It moves an unlocked block to a queue place worked out from a time: before the first other unlocked block (automatic changeovers aside) whose midpoint is after that time, or to the end. So a drop on the left half of a bar goes before it and on the right half after it; a drop after the last job goes to the end, and one before the queue start goes first. It never puts a job ahead of a started job (that would move it), never changes the queue start, and rebuilds changeovers as usual. Dragging a locked block moves its pinned time instead (`#lock(block, starts_at:)`, snapped to the slot; Q75), and so does dragging maintenance on the timeline, which is then fixed there even if it was in the queue (Q80); in the queue table it's only reordered. A block can't be fixed at a time that overlaps a started job, since that would push the running job back. Automatic changeovers, started jobs and blocks on a read-only plan can't be dragged.
  - Controller: `PATCH /planner/blocks/:id/drop` with `at` (the drop time) on `ScheduleBlocksController`, using the existing `set_block`, `keep_live_plan_while_drafting`, `done` and `failed`, so it works on drafts and returns the board as a Turbo Stream. The notice says where the job ended up ("SO-00012 now runs Tue 14:00 → Wed 02:30"), as reflow can land it away from the drop point.
  - UI: a `planner-drag` Stimulus controller on the timeline, using pointer events (no SortableJS or other new dependency). Bars that can move get `data-drop-url`; each day's track gets its start time and slot count, so the drop point gives a 30-minute slot and a time (clock-change days still work). A mouse drag starts after a few pixels, so a click still opens Edit; on touch, a press-and-hold starts it, so the timeline can still scroll sideways. While dragging, a ghost bar follows the slot under the pointer with its time, the board is marked busy, and Escape or dropping outside the tracks cancels. The drop submits a hidden form with `requestSubmit()`, so Turbo handles the stream. Drags stay within the week shown; further moves use the buttons or Edit.
  - Queue table: the same controller reorders rows by drag (handle at the start of each movable row), using the existing `move_to` with a `position`.
  - Tests: editor unit tests for `move_to_time` (each half of a bar, past the end, before the start, not ahead of a started job, changeovers rebuilt, on a draft) and for dragging a locked block; controller tests for `drop` (unlocked, locked, live plan while drafting, started job, automatic changeover, floor user refused); system tests dragging a bar with mouse actions and a queue row, on the live plan and in a draft.
  - Also: Help page (Planner section) and CLAUDE.md (planner rules) updated; the Phase 3 item is ticked off here.
  - Built as: `Schedule::Editor#move_to_time`, `ScheduleBlocksController#drop` (`PATCH /planner/blocks/:id/drop`), `PlannerHelper#drag_data` / `#draggable_block?`, and `planner_drag_controller.js` on `#planner_board` (bars on the timeline and ⠿ handles in the queue; a hidden form submits the drop through Turbo). The ghost bar shows the new start time while dragging; resting near the window's top or bottom, or the timeline's sides, scrolls. Queue rows drop only on queued rows (not locked blocks or automatic changeovers). Working assumptions Q74–Q75 are in §11.
- [x] **Slice 11 – Optimise the plan** (Daz, 24 Nov 2026): an **Optimise** button on the planner replans both lines around the orders' required dates, into a draft plan for the planner to check and publish.
  - Model: `Schedule::Optimise.new(draft.plan).call`. Jobs not started, for orders still to make, are reordered and may move to the other line when it has a rate for the spec; order lines with weight still to plan get a job for the rest (Q77). Locked blocks never move; started jobs and other unlocked blocks keep their place in the queue and jobs fill the places between them, except "no orders" blocks, which go after the last job; automatic changeovers are rebuilt and the planner's own unlocked changeovers are dropped (Q79). Urgent orders' jobs go first on their line (Q78). Best means, in order: fewest late orders, fewest minutes late, fewest changeovers, jobs finishing earliest (Q76); ties come out in random order.
  - Method: required-date order (urgent first, ties shuffled), each job on the line where the plan scores best; then moves of one job, a run of same-spec jobs, or a swap of two jobs, kept when the score improves, until nothing does. Several runs from different shuffles (up to 10, within 3 seconds); the best is kept. Times are worked out like `Schedule::Reflow` with integer seconds.
  - Writes through the new `Schedule::Editor#rearrange(queue)` (the line's whole queue in one edit; a job changing line becomes a new block there and its old block comes off, so `Schedule::Publish` adds and removes them).
  - UI: `POST /planner/optimise` (`PlanOptimisationsController`), on the live plan (starts a draft) and on a draft. The notice gives late orders and changeovers before and after, the late orders, jobs added and moved, and order lines no line has a rate for.
  - Tests: `Schedule::Optimise` unit tests (date order, both lines, same-spec runs, urgent first, unplanned order lines, rates per line, locked and started blocks, same seed same plan, publish after a move), controller and system tests. Help page (Prepare a new plan) and CLAUDE.md updated.

## 7. Phase 2 — Shop floor & scanning
- [ ] `/floor` touch UI: big-button screens for "Load material", "Start run", "Finish reel", "Goods in".
- [ ] Scanner input: a Stimulus controller that captures fast keyboard input ending in Enter and routes it (lot code → lot, reel code → reel).
- [ ] Zebra ZPL label printing for goods-in bags, reels and pallets (per-customer label templates from spec labelling instructions).
- [ ] Hopper/drier load tracking by scan.
- [ ] Offline tolerance: queue scans locally if the Wi‑Fi drops (only if it turns out to be a real problem).

## 8. Phase 3 — Smarter planning & integration
- [ ] Changeover matrix (spec A → spec B minutes; width/thickness/silicone changes).
- [ ] ~~Drag-and-drop planner (Stimulus + SortableJS).~~ Brought forward as Slice 10, with no SortableJS.
- [ ] Material requirements: plan × recipes vs stock + open POs → shortfall report and suggested POs.
- [ ] Sage API integration (confirm Sage product first) — push customers and invoices.
- [ ] Reports: tonnes per line/week, scrap %, recycled content % per order (useful for Plastic Packaging Tax evidence), lot traceability (finished reel → every input lot and supplier, and the reverse).
- [ ] Job costing: material cost from lot prices + line hourly cost.

## 9. Phase 4 — Nice to have
- [ ] Machine data (line speed, output) via the line PLC/OPC UA if the equipment supports it.
- [ ] Customer portal: order status and delivery notes.
- [ ] Dashboards on a plant TV (Turbo Streams live updates).

---

## 10. Using Claude Code well on this project
- Keep `CLAUDE.md` and `PLAN.md` at the repo root. CLAUDE.md holds the stack, domain rules and design rules.
- Start each session with: *"Read CLAUDE.md and PLAN.md. Plan Slice N, show me the plan, then build it with tests."*
- Use plan mode for Slices 3, 4 and 7 (the tricky ones).
- Commit after each slice. Small slices = easy review.
- Give Claude real sample data early (anonymised specs, a real PO, the production record sheet) — it makes the forms right first time.
- Show your friend the planner after Slice 4. That's the moment to catch wrong assumptions.

## 11. Questions for Stu, with working assumptions
We're building ahead of some answers. Each question has a **best guess** that the app uses for now, plus where it shows up, so it's quick to correct. When an answer comes back, tick the box, write the answer under it, and fix anything listed in **Update**.

- [ ] **Q1. Which Sage exactly (Sage 50 / Sage Business Cloud / Sage 200)?**
  - Guess: Sage 50 with its Audit Trail Transactions CSV import (sales invoices, type SI), built in Slice 8. Order lines have an optional price per tonne so the export has amounts to send; a note without one waits.
  - Update: Slice 8 export format. Drop `sales_order_lines.price_per_tonne_cents` if Sage prices invoices itself.
- [ ] **Q2. Rough kg/hour per line for typical specs? Does it vary much by width/thickness?** (Log 731: 10,040 kg in ~52 h including a gap. Was that a stop?)
  - Guess: 150–230 kg/h, a bit faster on D1. Seeded per spec as `LineRate`s.
  - Update: `db/seeds.rb` rates, plus the real rates entered on each spec page.
- [ ] **Q3. Typical changeover times? Do they depend on what changes (micron, width, silicone)?**
  - Guess: a flat 60 min on D1 and 90 min on D2 (`lines.default_changeover_minutes`). There's no spec-to-spec matrix until Phase 3.
  - Update: line settings and seeds. Bring the changeover matrix forward if it varies a lot.
- [ ] **Q4. A sample delivery note and the current reel/pallet labels.**
  - Guess: the Slice 8 delivery note is laid out from the fields we hold: our details, customer and delivery address, our order and their PO, haulier and vehicle, one row per pallet (reels, reel numbers, net kg), totals and a "received in good condition" box. Labels are still Phase 2.
  - Update: `DeliveryNotePdf` to match his sample.
- [ ] **Q5. Is "Virgin Co‑Ex" the shared capping polymer? One shared hopper, or split into each line?**
  - Guess: yes, Co‑Ex is the capping layer, fed from one shared hopper. Seeded as the "Capping polymer" category.
  - Update: §4 allocation design (Slice 7c) if each line has its own hopper.
- [ ] **Q6. What % of each stream (Co‑Ex / Main‑Ex / PCW / Regrind) goes into a typical spec? Do recipes vary by spec?**
  - Guess: every spec uses a standard recipe of Co-Ex 15%, Main-Ex 50%, PCW 25%, Regrind 10% until it's given its own on the spec page (Slice 7c). The demo spec BF-700-250 has its own (12/48/30/10).
  - Update: `ProductSpec::Recipe::STANDARD_BP`, and enter the real recipe on each spec. If a stream's share varies run to run, record it on the log instead.
- [ ] **Q7. How is regrind made and labelled today? Is it weighed into bags?**
  - Guess: edge trim is reground into weighed bags with our own lot codes. Seeded as the in-house material "Regrind chip".
  - Update: Slice 6/7c lot handling for regrind.
- [ ] **Q8. Who uses it: office only at first, or operators too? How many users?**
  - Guess: office and floor from the start, about 10 users, with roles admin/office/floor.
- [ ] **Q9. Does he need recycled-content % reporting (Plastic Packaging Tax / customer certificates)?**
  - Guess: yes, later (Phase 3 reports). Nothing to build yet.
- [ ] **Q10. Is the second line "D2"? Do both lines use the same forms?**
  - Guess: yes, D1 and D2, and both use forms 5.4.1.1 and 5.4.1.2.
  - Update: line names in seeds or on the Lines screen.

### Slice 2 (sales orders) assumptions
- [ ] **Q11. How are our order numbers written?** Guess: `SO-00001`, then `SO-00002` and so on. The customer's own PO ref (e.g. `M15159`) is stored separately. Update: `SalesOrder.next_number`.
- [ ] **Q12. Is the required date per order or per line?** Guess: per order. If one order can have lines due on different dates, move `required_on` onto `sales_order_lines`.
- [ ] **Q13. Is the order quantity exact, or is ± some % acceptable?** Guess: a target in kg with no tolerance stored. Update: add `tolerance_bp` to lines if over- or under-runs are agreed per order.
- [ ] **Q14. Can one customer PO cover several specs?** Guess: yes, one order with several lines (one spec per line).

### Slice 3 (planner) assumptions
- [ ] **Q15. Does a job pause for planned maintenance or an engineer visit and carry on afterwards?** Guess: no. Jobs aren't split. A job that won't finish before a locked block starts moves after it, and the line shows as idle (warning). Update: `Schedule::Reflow#first_free_start` would split jobs instead.
- [ ] **Q16. When is a job "late"?** Guess: when it finishes after the end of the order's required day (UK time), with no allowance for QA, packing or transport. Update: `Schedule::Warnings#late` (add a buffer, or compare with the start of the day).
- [ ] **Q17. Is a changeover needed between two jobs for the same spec?** Guess: no. A changeover is only added automatically between jobs for different specs, using the line's default minutes. Update: `Schedule::Editor#needs_changeover?`, and the Phase 3 changeover matrix.


### Slice 5 (purchasing) assumptions
- [ ] **Q18. How are our PO numbers written, and is there a current number to carry on from?** Guess: `PO-00001`, then `PO-00002`, separate from sales orders. Update: `numbered_with "PO"` in `PurchaseOrder`, or seed the first number.
- [ ] **Q19. What company details go on a PO?** (company name, address, delivery address if different, phone, purchasing email, VAT and company numbers, standard terms.) Guess: placeholders ("Extrudle Demo Ltd") plus a short terms paragraph asking for our PO number on paperwork, labelled bags and a CoA with each delivery. Update: `config/company.yml`.
- [ ] **Q20. Are all materials bought per tonne in the supplier's currency? Is VAT shown?** Guess: yes, a price per tonne in the PO's currency (taken from the supplier, changeable until lines are added), net of VAT, with no VAT line on the PO. Each line total is rounded to the nearest penny/cent and the PO total is the sum of the lines. Update: `PurchaseOrderLine#total_cents` and the PDF if additives are priced per kg or VAT should be shown.
- [ ] **Q21. One delivery date per PO, or per line / call-offs?** (e.g. 88 t of JADE delivered as 4 × 22 t loads.) Guess: one expected delivery date per PO; call-offs are separate POs. Update: move `expected_on` to `purchase_order_lines` or add a deliveries table.
- [ ] **Q22. What happens when a PO changes after it's been sent?** Guess: only drafts can be edited. A sent PO is taken "back to draft", changed and sent again under the same number. There's no revision number or approval step. Update: `PurchaseOrder::EDITABLE_STATUSES`, and add a revision if suppliers need "PO-00012 rev 2".
- [ ] **Q23. Is the same material bought from more than one supplier?** Guess: yes, it can be. A PO line can use any bought-in material; the supplier's own materials are listed first. Update: `material_options_for` in `PurchaseOrdersHelper` if POs should only list that supplier's materials.
- [ ] **Q24. How do POs get to suppliers, and does anyone approve them?** Guess: office staff download the PDF and email it themselves, then (or before) click "Mark as sent". No approval step, and the app doesn't send email. Update: add a mailer (Resend/SMTP) or an approval status if needed.

### Slice 6 (goods in and stock) assumptions
- [ ] **Q25. Is every bag/octabin its own lot with its own label?** Guess: yes. Each bag gets a lot code and label, and keeps the supplier's batch number and bag number (the log's "JADE bag 939"). Update: `Stock::Receipt` if a whole delivery should be one lot.
- [ ] **Q26. How are bags weighed at goods in?** Guess: we take the total net weight from the delivery note and split it evenly across the bags. A bag found to be different is corrected with "Adjust weight". Update: `Stock::Receipt` to take a weight per bag if each bag's label shows its own net weight.
- [ ] **Q27. When is a PO line complete?** Guess: when at least the ordered weight has arrived. Over-deliveries are accepted. A short delivery stays "part received" until someone clicks "Close short". Update: `PurchaseOrder#refresh_receipt_status!` if there's an agreed tolerance (e.g. ±2%).
- [ ] **Q28. What are the stock locations in practice?** (Where is "storage"? Is stock ever held at the supplier or bought while in transit? Do you need named bays, silos or the drier?) Guess: the four fixed locations from the plan (on site, storage, at supplier, in transit), and bags always move whole. Update: `Lot::LOCATIONS`, or a locations table if he needs named places.
- [ ] **Q29. What labels can he print on today?** Guess: A4 sheets of 8 sticky labels (99 × 68 mm, Avery L7165 layout) on an ordinary printer, until Zebra label printers arrive in Phase 2. Update: the `.lot-sheet` CSS for a different sheet.
- [ ] **Q30. Is there an existing lot or bag numbering scheme we should use?** Guess: our own codes, `L-2026-000123`, restarting each year; the supplier's batch and bag numbers are kept alongside. Update: `Lot.next_codes`.
- [ ] **Q31. Who does goods in?** Guess: office staff for now, on the office screens. The floor goods-in screen comes in Phase 2. Update: allow `floor` in `GoodsReceiptsController` if operators receive deliveries.
- [ ] **Q32. How will opening stock be counted at go-live?** Guess: a stock count of every bag on site, entered with "Add stock without a PO" (one entry per material and batch), and labelled then. Update: Master data › Import › Opening stock (Slice 9) takes the count as a CSV.

### Slice 7a (production log) assumptions
- [ ] **Q33. How are despatch numbers handed out?** Guess: one per production log, counting up from the highest so far. Whoever starts the first log types in the next paper number (e.g. 732); after that it fills in by itself. Update: `ProductionRun.next_despatch_number`.
- [ ] **Q34. Is there one log per planned job, and only one log running on a line at a time?** (Or does a long job get a new log per day, shift or delivery?) Guess: one log per job, one running log per line. Update: `ProductionRun#one_running_log_per_line` and the unique `schedule_block_id`.
- [ ] **Q35. What exactly are the prestart checks on the form?** Guess: "Previous documents and labels removed" and "Previous product cleared from the line", answered Yes/No by the technician. Update: `ProductionRun::Checklist::YES_NO`.
- [ ] **Q36. What are the width and thickness tolerances? Do they vary by customer or spec?** Guess: width ±2 mm and thickness ±5% (238–262 µm for 250 µm), for every spec. Update: `ProductionRun::Checklist` constants, or tolerance fields on `ProductSpec`.
- [ ] **Q37. When are width and thickness measured?** Guess: at start-up (as many readings as they like) and again at the end of the run (Slice 7b). Update: `ProductionRun::Checklist::MEASURED_STAGES`, or readings per reel in Slice 7b.
- [ ] **Q38. Should starting a run change the plan?** Guess: no. The order goes "in production" and the job can't be removed from the plan, but the planner re-times the line if the job started early or late. Update: `ProductionRun::Start` could lock the job at its real start time.
- [ ] **Q39. Who fills in the log?** Guess: the technicians on a floor screen (floor users see it in large type); the office can read and correct it. Technicians are typed names, not user accounts. Update: `technician_days`/`technician_nights` would become users if each technician signs in.

### Slice 7b (reels and finishing) assumptions
- [ ] **Q40. What are the end-of-run and line clearance checks on the form?** Guess: width and thickness measured on the last reel, then "Materials cleared from the line", "Log, labels and documents removed" and "Line cleared for the next micron", each Yes/No. Update: `ProductionRun::Checklist::YES_NO["line_clearance"]`.
- [ ] **Q41. What has to be done before a log is closed?** Guess: at least one reel, both end readings, every line clearance check answered Yes, and a comment or corrective action if an end reading is out of tolerance. Update: `ProductionRun#finish_problems`.
- [ ] **Q42. How are pallets numbered?** Guess: 1, 2, 3… within each despatch. The next reel goes on the same pallet until it holds the spec's reels per pallet (one reel per pallet if the spec doesn't say); the technician can change it. Update: `ProductionRun#suggested_pallet_no`, and Slice 8 when pallets get their own records.
- [ ] **Q43. How are mistakes on the reel sheet corrected? Can a finished log be reopened?** Guess: any reel can be edited (with a note) while the log is open; only the last reel can be removed, so numbers stay in sequence; finished logs can't be reopened. Update: `ReelsController#destroy`, and an admin "reopen" if needed.
- [ ] **Q44. What do the length and initials columns mean?** Guess: length in whole metres from the winder counter, optional; initials are whoever checked the reel against the spec, carried over from the last reel. Update: make length required, or initials a signed-in user.
- [ ] **Q45. What should a log's progress be measured against?** Guess: the whole order line ("of 20 t ordered"), so a line split into two jobs shows each run at about 50% when its job is done. Update: `ProductionRun#percent_of_order` could use the job's planned weight (`schedule_block.planned_g`) instead, or show both.

### Slice 7c (material loads and allocation) assumptions
- [ ] **Q46. Should material used be the reel weight, or more to allow for edge trim and scrap?** Guess: the weight of reels made, split by the recipe. Trim and scrap show up as each bag's variance when it's marked empty. Update: `ProductionRun::MaterialUse#feed_totals` (add a scrap % per line or spec).
- [ ] **Q47. When one log ends and the next starts on the same line, do the bags on the feeds carry on?** Guess: yes. Bags still on the feeds (not marked empty) are added to the next log on that line from reel 1, marked "From last log". Update: `ProductionRun::Start#carry_over_bags`.
- [ ] **Q48. When a new bag goes on a feed, is the last one always empty?** Guess: usually. The box "The bag it replaces is empty" is ticked by default; untick it for a part-used bag coming off, which stays in stock with its book weight. Update: the default of `ProductionRun::LoadMaterial#previous_empty`.
- [ ] **Q49. Can the same Co-Ex bag feed both lines at once?** (Follows on from Q5.) Guess: yes, Co-Ex only: the same bag can be recorded on both lines' logs, and each log is allocated its share. Any other bag is on one feed of one line at a time. Update: `MaterialLoad::SHARED_FEEDS`.
- [ ] **Q50. What variance on a bag is worth looking into, and who checks?** Guess: the office looks at "Bags on the lines and variance" under Stock; more than 5% either way is flagged. Update: `Stock::Variance::FLAG_BP`.
- [ ] **Q51. Are additives (antiblock, silicone, masterbatch) taken off stock too?** Guess: not yet. Their batch numbers are written on the log header (Slice 7a) and they aren't fed through the four feeds, so their stock is corrected by stock counts. Update: add additive feeds and shares to the recipe.

### Slice 7d (printable log) assumptions
- [ ] **Q59. Could we have a scan of a filled-in form 5.4.1.2 (both pages)?** Guess: A4 portrait laid out from the fields we know: page 1 is the header boxes, batch numbers, prestart and start-up checks and the material bags; page 2 starts the reel sheet, then the end of run and sign-off. Update: `ProductionLogPdf` to match the paper layout.
- [ ] **Q60. Does a printed log need signing for ISO, and by whom?** Guess: the app records who started and finished the log, and the printout has two signature lines: the technician and a QA check. Update: `ProductionLogPdf#sign_off`.
- [ ] **Q61. Should a log that's still running be printable?** Guess: yes (e.g. to hand over at a shift change), with every page marked "In progress: not the final record". Update: allow only finished logs in `ProductionRunsController#show`.
- [ ] **Q62. How are logs kept for audits: printed and filed, or kept in the app?** Guess: kept in the app. A finished log can't change, so its PDF is made fresh each time and always reads the same. Update: save a copy of the PDF when a log is finished if auditors need the exact file, and agree how long logs are kept.

### Slice 7e (draft plans) assumptions
- [ ] **Q52. While a draft is open, can the live plan still be changed?** Guess: not by the planner: the live plan is read-only until the draft is published or discarded. Starting a job and cancelling an order still work, because the factory doesn't stop. Update: `ScheduleBlocksController#keep_live_plan_while_drafting`.
- [ ] **Q53. Who can start, publish or discard a draft?** Guess: anyone who can use the planner (admin and office). There's one draft at a time and anyone can carry on with it. Update: the roles on the draft plan controller.
- [ ] **Q54. What happens to a draft that's never published?** Guess: it stays until someone publishes or discards it; the planner shows how old it is. Update: discard drafts automatically after a number of days.
- [ ] **Q55. What does publishing do with what happened meanwhile?** Guess: a job started since the draft began stays as it really is (it can't be moved or removed); jobs for orders cancelled meanwhile come off the draft as soon as the order is cancelled; orders added meanwhile appear under "Orders to plan" in the draft. All of this is listed before Publish. Update: `Schedule::Publish` (`#notes` and `#publish_line`).

### Slice 8 (dispatch and Sage) assumptions
- [ ] **Q63. Which Sage nominal code and VAT codes do sales go to?** Guess: nominal 4000, department 0, VAT code T1 (20%) for UK customers and T4 (0%) for EU customers, set per customer with their Sage account reference. Update: `config/sage.yml` and each customer's Sage fields.
- [ ] **Q64. When is a pallet ready to go?** Guess: once its log has finished, a later pallet has been started, or it holds the spec's reels per pallet. Pallets can go out while a long run carries on (up to 3 deliveries a log). Update: `Pallet#complete?`.
- [ ] **Q65. How are delivery notes numbered?** Guess: our own `DN-00001`, `DN-00002`… separate from despatch numbers, as one load can carry pallets from more than one log. Update: `numbered_with "DN"` in `DeliveryNote`.
- [ ] **Q66. When is an order "dispatched"?** (Follows on from Q13.) Guess: once every line has gone out in full by weight. A short delivery is closed by hand ("Mark dispatched" on the order); over-runs are fine. Update: `SalesOrder#refresh_dispatch_status!`.
- [ ] **Q67. How should invoices go into Sage?** Guess: one invoice line per spec on each delivery note, at the order's price per tonne, dated the dispatch date, with the delivery note number as the reference and their PO as the extra reference. Non-GBP customers are exported in their own currency, leaving the exchange rate to Sage. Update: `SageExport.rows_for`.
- [ ] **Q68. Who does dispatch: the office or the warehouse?** Guess: the office, on the office screens; nothing on the floor screens yet. Update: the roles on `DispatchController`, `DeliveryNotesController` and `SageExportsController`.

### Slice 8a (approved computers) assumptions
- [ ] **Q56. Who can sign in from a computer that isn't approved?** Guess: only Stu's admin account. Any admin can approve the computer they're signed in on, but only from an approved one or as Stu. Update: `users.sign_in_anywhere` and `Admin::DevicesController`.
- [ ] **Q57. Phones and tablets?** Guess: approved the same way as any computer, one browser at a time. Clearing the browser's data or using a different browser counts as a new computer and needs approving again. Update: nothing; it's how the cookie works.
- [ ] **Q58. Should the preview at stu.daz.codes require approval too?** Guess: no, so Stu can show it to people; it's switched on for the real deploy. Update: `REQUIRE_APPROVED_COMPUTERS` in `config/deploy.yml`.

### Slice 9 (go-live) assumptions
- [ ] **Q69. What spreadsheets are there for customers, suppliers, specs and stock, and what are the columns called?** Guess: they can be saved as CSV and their columns renamed to match our templates (common alternative names are understood). Customers, suppliers and materials are matched by name, specs by code; an import never clears a field. Update: the columns and aliases in `app/models/import/*.rb`.
- [ ] **Q70. How long should backups be kept, and who should hear if one fails?** Guess: 30 days, restorable to any moment, with the latest backup restored and checked every night. A failed check shows under Users › Backups; nobody is emailed yet. Update: `retention` in `config/litestream.yml`, and add a mailer to `BackupRestoreCheckJob`.
- [ ] **Q71. Who needs training, and how?** Guess: the in-app Help page by job (floor, office, admin), a walk-through with each team, and the first week run on paper and in Extrudle side by side. Update: `app/views/help/show.html.erb`.
- [ ] **Q72. Blank paper logs: how many reels should fit, and what happens to them afterwards?** Guess: two A4 pages with 22 reel rows (most jobs are 10–20 reels). They're typed into Extrudle once it's back and kept with the printed log. Update: `BlankProductionLogPdf::REEL_ROWS`.
- [ ] **Q73. Planner colours: how should urgent jobs stand out once jobs are colour coded?** Guess: colour is only the customer's (lime unless chosen) or the job's own, and lemon is an ordinary choice. Urgent jobs get a black double border (its outer line red when late), which isn't one of the colour options, and keep the URGENT tag on bars of 3 hours or more. Colours are on the planner screen only, not the printed 5.4.1.1 plan. Update: `PlannerHelper#urgent_border`.

### Slice 10 (drag and drop) assumptions
- [ ] **Q74. When a job is dragged to a time, should it go into the queue there or be pinned at that exact time?** Guess: into the queue (chosen 24 Nov 2026, to confirm with Stu): jobs keep running back to back, so the job lands as near the drop point as the queue allows and everything after it reflows. Pinning stays on the Edit page. Update: `ScheduleBlocksController#drop`.
- [ ] **Q75. What does dragging a locked block (maintenance, an engineer visit, a locked job) do?** Guess: it moves the block's pinned start to the slot it was dropped on, and the queue reflows around it. Update: `ScheduleBlocksController#drop`.

### Slice 11 (optimise the plan) assumptions
- [ ] **Q76. What does "optimal" mean for the plan?** Guess: in order, the fewest late orders, then the fewest minutes late in all, then the fewest changeovers, then jobs finishing as early as possible. Jobs that tie on all four come out in random order, so pressing Optimise again can give a different plan that's just as good. Update: `Schedule::Optimise::Score`.
- [ ] **Q77. Should Optimise also plan orders that aren't on the plan yet?** Guess: yes, every order line still to make gets a job for its unplanned weight, on a line with a rate for its spec. Lines no line has a rate for are listed and left off. Update: `Schedule::Optimise#add_unplanned_tasks`.
- [ ] **Q78. Do urgent orders always go first?** Guess: yes, their jobs go ahead of every other job not started on their line, whatever the dates. Update: `Schedule::Optimise#allowed_places`.
- [ ] **Q79. What happens to blocks Optimise can't move?** Guess: locked blocks keep their time; started jobs, maintenance and "no orders" blocks in the queue keep their place in it. Changeovers the planner added by hand are dropped, because the job order around them changes; automatic ones are rebuilt. Update: `Schedule::Optimise#read_line`.
- [ ] **Q80. Should dragging maintenance fix it at the time it's dropped on?** Guess: yes (25 Nov 2026, after Stu couldn't drag a maintenance block from Wednesday to Thursday: it was in the queue, so the drop only reordered it and it flowed back next to the same jobs). Maintenance is usually booked for a time, so a dragged planned or unplanned maintenance block is locked at the drop time and jobs move round it (a job it lands on runs after it, never split). Jobs, "no orders" and changeovers still reorder (Q74), and maintenance dragged in the queue table is only reordered. It can't be fixed over a job that has started. Update: `ScheduleBlocksController#drop`.
