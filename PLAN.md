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
  - Deferred: `SpecIngredient` recipes (waiting on stream % from §11 Q6, needed by Slice 7c) and locking used specs into new revisions (Slice 2, once orders reference specs).
- [x] **Slice 2 – Sales orders**: orders with lines (spec dropdown pre-fills spec details read-only, quantity in kg/tonnes toggle), status, list filtered by required date.
  - Also: spec revision locking (edits to a spec on an order create the next revision). Statuses after `open` are only reachable by cancel/reopen until Slices 3–8 set them. Working assumptions Q11–Q14 are in §11.
- [x] **Slice 3 – Planner model**: `ScheduleBlock`, duration calc, `Schedule::Reflow` service, locked blocks, warnings. Heavy unit tests here.
  - Built as `ScheduleBlock`, `Schedule::Reflow`, `Schedule::Editor` (add/insert/move/resize/replan/lock/unlock/remove/start_at, automatic changeovers) and `Schedule::Warnings` (late, no rate, over-planned, idle before a locked block). Orders switch between open and scheduled automatically. Assumptions: §11 Q15–Q17.
- [x] **Slice 4 – Planner UI**: per-line week timeline (48 slots/day), add job from an unscheduled order line, add changeover/maintenance/no-orders blocks, move up/down buttons (Turbo Streams), print view.
  - `/planner`: a tab per line, week navigation, and a day × 48-slot CSS grid timeline (46/50 slots on clock-change days) with a now line. A queue list with ▲ ▼ / edit / remove (Turbo Streams), "Orders to plan" (most pressing first, estimated time on this line), and "Add a block" (kind, hours, position, optional fixed time). A block edit page covers weight, hours, lock and notes. `/planner/print` is laid out like form 5.4.1.1, landscape A4, with start/finish times and urgent/late rows marked. Drag-and-drop is still Phase 3.
- [x] **Slice 5 – Purchasing**: POs with currency, incoterms, lines in kg, price/tonne; PO PDF; status (draft/sent/part-received/received).
  - Also: draft → sent → back to draft to amend, cancel/reopen. `part_received`/`received` are set by goods in (Slice 6). Our company details for the PDF are placeholders in `config/company.yml`. Working assumptions Q18–Q24 are in §11.
- [ ] **Slice 6 – Goods in & stock**: receive against a PO line → creates Lots + StockMovements; set location (on site/storage/at supplier/in transit); transfer between locations; stock-on-hand by material and category; printable lot labels (A4 sheet of QR codes is fine for MVP).
- [ ] **Slice 7a – Production log (header and checks)**: start a run from a schedule block. It gets a despatch number and pre-fills customer, order, spec, gauge, width and material type. Record additive batch nos, technicians and prestart checks. Width/thickness target vs actual is shown red/green.
- [ ] **Slice 7b – Reel entry**: a fast touch-friendly grid replacing page 2 of the log, with reel no, time (auto), weight, length, pallet and initials. Show a running total and a "% of order" bar. End-of-run checks and line clearance follow.
- [ ] **Slice 7c – Material loads and allocation**: record bags per feed against reel ranges, using a lot-code field that a scanner can fill later. Allocation and reconciliation as in §4. Stock deducts automatically.
- [ ] **Slice 7d – Printable log**: a PDF that looks like the current 5.4.1.2 form, for audits and ISO records.
- [ ] **Slice 8 – Dispatch**: pallets from reels, delivery note PDF, mark order dispatched; **Sage CSV export** of dispatched-but-not-invoiced notes.
- [ ] **Slice 9 – Polish & go-live**: import real specs/customers/suppliers from spreadsheets (CSV importer), Litestream backups to R2 plus a tested restore, user training notes. Printable blank 5.4.1.2 logs as a paper fallback if the system is down.

## 7. Phase 2 — Shop floor & scanning
- [ ] `/floor` touch UI: big-button screens for "Load material", "Start run", "Finish reel", "Goods in".
- [ ] Scanner input: a Stimulus controller that captures fast keyboard input ending in Enter and routes it (lot code → lot, reel code → reel).
- [ ] Zebra ZPL label printing for goods-in bags, reels and pallets (per-customer label templates from spec labelling instructions).
- [ ] Hopper/drier load tracking by scan.
- [ ] Offline tolerance: queue scans locally if the Wi‑Fi drops (only if it turns out to be a real problem).

## 8. Phase 3 — Smarter planning & integration
- [ ] Changeover matrix (spec A → spec B minutes; width/thickness/silicone changes).
- [ ] Drag-and-drop planner (Stimulus + SortableJS).
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
  - Guess: Sage 50 with a CSV import, built in Slice 8. Order lines have an optional price per tonne so the export has amounts to send.
  - Update: Slice 8 export format. Drop `sales_order_lines.price_per_tonne_cents` if Sage prices invoices itself.
- [ ] **Q2. Rough kg/hour per line for typical specs? Does it vary much by width/thickness?** (Log 731: 10,040 kg in ~52 h including a gap. Was that a stop?)
  - Guess: 150–230 kg/h, a bit faster on D1. Seeded per spec as `LineRate`s.
  - Update: `db/seeds.rb` rates, plus the real rates entered on each spec page.
- [ ] **Q3. Typical changeover times? Do they depend on what changes (micron, width, silicone)?**
  - Guess: a flat 60 min on D1 and 90 min on D2 (`lines.default_changeover_minutes`). There's no spec-to-spec matrix until Phase 3.
  - Update: line settings and seeds. Bring the changeover matrix forward if it varies a lot.
- [ ] **Q4. A sample delivery note and the current reel/pallet labels.**
  - Guess: nothing yet. Needed by Slice 8 (delivery note PDF) and Phase 2 (labels).
- [ ] **Q5. Is "Virgin Co‑Ex" the shared capping polymer? One shared hopper, or split into each line?**
  - Guess: yes, Co‑Ex is the capping layer, fed from one shared hopper. Seeded as the "Capping polymer" category.
  - Update: §4 allocation design (Slice 7c) if each line has its own hopper.
- [ ] **Q6. What % of each stream (Co‑Ex / Main‑Ex / PCW / Regrind) goes into a typical spec? Do recipes vary by spec?**
  - Guess: none yet. `SpecIngredient` recipes are deferred until we know, and Slice 7c needs them.
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
