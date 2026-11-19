# Demo data. Idempotent: safe to run more than once (bin/rails db:seed).
# All company names are fictional.
#
# Production never gets the demo users unless DEMO_SEEDS=true (the stu.daz.codes
# preview), and then their password comes from credentials (demo_password), not
# this repo. Kamal runs db:prepare, which seeds a fresh database, so otherwise
# production only gets the first admin, and only from ADMIN_EMAIL / ADMIN_PASSWORD.

demo_in_production = Rails.env.production? && ENV["DEMO_SEEDS"] == "true"

if Rails.env.production? && !demo_in_production
  email, password = ENV["ADMIN_EMAIL"], ENV["ADMIN_PASSWORD"]

  if email.present? && password.present?
    User.find_or_create_by!(email_address: email) do |user|
      user.assign_attributes(name: ENV.fetch("ADMIN_NAME", "Admin"), role: "admin", password: password)
    end
    puts "Ensured admin user #{email}"
  else
    puts "Skipping seeds in production. Set ADMIN_EMAIL and ADMIN_PASSWORD to create the first admin."
  end
  return
end

DEMO_PASSWORD = if demo_in_production
  Rails.application.credentials.demo_password.presence || raise("DEMO_SEEDS needs demo_password in credentials")
else
  "extrudle-demo"
end

# On the preview, Stu signs in with his own address (credentials: demo_admin_email).
stu_email = (Rails.application.credentials.demo_admin_email.presence if demo_in_production) || "admin@extrudle.test"

[
  { name: "Stu Kershaw",  email_address: stu_email,              role: "admin" },
  { name: "Jess Kershaw", email_address: "office@extrudle.test", role: "office" },
  { name: "Eric Kershaw", email_address: "floor@extrudle.test",  role: "floor" }
].each do |attrs|
  User.find_or_create_by!(email_address: attrs[:email_address]) do |user|
    user.assign_attributes(attrs.merge(password: DEMO_PASSWORD))
  end
end

# --- Lines -------------------------------------------------------------------
lines = [
  { name: "D1", machine_no: "1", default_changeover_minutes: 60, position: 1 },
  { name: "D2", machine_no: "2", default_changeover_minutes: 90, position: 2 }
].to_h { |attrs| [ attrs[:name], Line.find_or_create_by!(name: attrs[:name]) { _1.assign_attributes(attrs) } ] }

# --- Customers ---------------------------------------------------------------
customers = [
  [ "Brightform Packaging Ltd", "Hannah Cole", "GBP", "Unit 7, Brightform Park\nLeeds\nLS10 1AB" ],
  [ "Castleton Thermoforming", "Raj Patel", "GBP", "Castleton Works, Mill Lane\nSheffield\nS9 2RT" ],
  [ "Delta Blister Solutions", "Mark Ellis", "GBP", "14 Delta Way\nTelford\nTF3 3BD" ],
  [ "Fenwick Medical Trays", "Sarah Odum", "GBP", "Fenwick House, Kingsway\nGateshead\nNE11 0SX" ],
  [ "Greenway Punnets", "Tom Hirst", "GBP", "Greenway Farm Estate\nSpalding\nPE11 3YT" ],
  [ "Harbour Point Displays", "Lucy Barnes", "GBP", "3 Harbour Point\nBristol\nBS11 9FG" ],
  [ "Kestrel Food Packaging", "Ian McLeod", "GBP", "Kestrel Road\nLivingston\nEH54 5DA" ],
  [ "Lumen Cosmetics Packaging", "Amira Shah", "EUR", "ZI des Bruyères, 8 rue Lumière\n27000 Évreux\nFrance" ],
  [ "Northgate Clamshells", "Dan Price", "GBP", "Northgate Industrial Park\nWarrington\nWA2 8TX" ],
  [ "Orchard Fresh Containers", "Megan Lloyd", "GBP", "Orchard Way\nEvesham\nWR11 1BP" ],
  [ "Pennine Industrial Trays", "Chris Walsh", "GBP", "Unit 22, Pennine Business Park\nHuddersfield\nHD2 1GQ" ],
  [ "Rhine Valley Verpackung GmbH", "Jonas Weber", "EUR", "Industriestraße 12\n67059 Ludwigshafen\nGermany" ]
].to_h do |name, contact, currency, address|
  # Sage 50 style account references (BRIGHT01). EU customers use T4, the rest T1.
  sage_ref = "#{name.gsub(/[^A-Za-z]/, "").first(6).upcase}01"
  customer = Customer.find_or_create_by!(name: name) do
    _1.assign_attributes(contact_name: contact, currency: currency, address: address, sage_account_ref: sage_ref,
                         sage_tax_code: currency == "EUR" ? "T4" : "T1")
  end
  # Fill in what was added to the seeds after this customer was created (the preview keeps its data).
  missing = { address: address, sage_account_ref: sage_ref }.select { |field, _| customer[field].blank? }
  missing[:sage_tax_code] = "T4" if currency == "EUR" && missing.key?(:sage_account_ref)
  customer.update!(missing) if missing.any?
  [ name, customer ]
end

# --- Suppliers ---------------------------------------------------------------
suppliers = [
  [ "Albion Polymers", "United Kingdom", "GBP", "DAP" ],
  [ "Baltic Resin Trading", "Poland", "EUR", "FCA" ],
  [ "Circular Flake Co", "United Kingdom", "GBP", "DAP" ],
  [ "EuroCap Polymers BV", "Netherlands", "EUR", "DAP" ],
  [ "Iberia Recycling SL", "Spain", "EUR", "CPT" ],
  [ "Midlands Masterbatch", "United Kingdom", "GBP", "DAP" ],
  [ "Pacific Resin Exports", "Malaysia", "USD", "CIF" ],
  [ "Silcoat Chemicals", "United Kingdom", "GBP", "EXW" ]
].to_h do |name, country, currency, incoterm|
  [ name, Supplier.find_or_create_by!(name: name) { _1.assign_attributes(country:, currency:, incoterm:) } ]
end

# --- Material categories and materials ---------------------------------------
categories = [
  [ "Virgin polymer", "Main-Ex virgin resin" ],
  [ "Capping polymer", "Co-Ex capping layer, shared by both lines" ],
  [ "Recycled (PCW and regrind)", "Post-consumer flake and in-house regrind" ],
  [ "Additives and masterbatch", "Antiblock, colour and slip" ],
  [ "Silicone", "Silicone coatings" ]
].each_with_index.to_h do |(name, description), index|
  [ name, MaterialCategory.find_or_create_by!(name: name) { _1.assign_attributes(description:, position: index + 1) } ]
end

[
  [ "JADE", "CZ-302", "Virgin polymer", "Pacific Resin Exports", "virgin", "purchased" ],
  [ "Albion Clear", "AC-80", "Virgin polymer", "Albion Polymers", "virgin", "purchased" ],
  [ "Baltic Virgin", "BV-76", "Virgin polymer", "Baltic Resin Trading", "virgin", "purchased" ],
  [ "EuroCap Co-Ex", "EC-200", "Capping polymer", "EuroCap Polymers BV", "virgin", "purchased" ],
  [ "Clear PCW flake", "Hot-washed", "Recycled (PCW and regrind)", "Circular Flake Co", "recycled", "purchased" ],
  [ "Iberia PCW flake", "Grade A", "Recycled (PCW and regrind)", "Iberia Recycling SL", "recycled", "purchased" ],
  [ "Regrind chip", nil, "Recycled (PCW and regrind)", nil, "recycled", "internal" ],
  [ "Antiblock masterbatch", "AB-5", "Additives and masterbatch", "Midlands Masterbatch", "virgin", "purchased" ],
  [ "Blue tint masterbatch", "BT-12", "Additives and masterbatch", "Midlands Masterbatch", "virgin", "purchased" ],
  [ "Silicone emulsion", "SE-35", "Silicone", "Silcoat Chemicals", "virgin", "purchased" ]
].each do |name, grade, category, supplier, origin, source|
  Material.find_or_create_by!(name: name) do |material|
    material.assign_attributes(grade:, material_category: categories.fetch(category),
                               supplier: supplier && suppliers.fetch(supplier), origin:, source:)
  end
end

# --- Product specs and line rates --------------------------------------------
# [code, customer, width mm, micron, silicone, silicone %, antiblock, PE, D1 kg/h, D2 kg/h, extras]
[
  [ "BF-700-250", "Brightform Packaging Ltd", 700, 250, "underside", "0.5", true, false, 190, 175, { customer_part_no: "BF-2231" } ],
  [ "BF-650-300", "Brightform Packaging Ltd", 650, 300, "underside", "0.5", true, false, 195, 180, {} ],
  [ "CT-820-400", "Castleton Thermoforming", 820, 400, "none", nil, false, false, 210, 200, { reels_per_pallet: 1 } ],
  [ "DB-560-200", "Delta Blister Solutions", 560, 200, "both", "0.8", true, false, 165, nil, { customer_tool_no: "T-118" } ],
  [ "FM-600-350", "Fenwick Medical Trays", 600, 350, "none", nil, false, true, 180, 170, { label_inside_core: true, packaging_notes: "Best-quality pallets only." } ],
  [ "GP-750-275", "Greenway Punnets", 750, 275, "reverse", "0.4", true, false, 200, 190, {} ],
  [ "KF-900-450", "Kestrel Food Packaging", 900, 450, "none", nil, false, true, 220, 205, { core_inches: 3 } ],
  [ "LC-500-180", "Lumen Cosmetics Packaging", 500, 180, "underside", "0.6", true, false, 150, nil, { packaging_notes: "Least adhesive tape on core." } ],
  [ "OF-700-250", "Orchard Fresh Containers", 700, 250, "underside", "0.5", true, false, 190, 175, { customer_product_code: "OF-PUN-250" } ],
  [ "STK-1000-500", nil, 1000, 500, "none", nil, false, false, 230, 215, { reel_limit: "max_roll_on_side" } ]
].each do |code, customer, width, micron, silicone, silicone_pct, antiblock, pe, d1, d2, extras|
  spec = ProductSpec.find_or_create_by!(code: code, revision: 1) do |s|
    s.assign_attributes({
      customer: customer && customers.fetch(customer), width_mm: width, thickness_micron: micron,
      silicone:, silicone_pct:, antiblock:, pe:, max_diameter_mm: 1000, max_reel_kg: "1100"
    }.merge(extras))
  end

  { "D1" => d1, "D2" => d2 }.each do |line_name, rate|
    next unless rate
    LineRate.find_or_create_by!(product_spec: spec, line: lines.fetch(line_name)) { _1.kg_per_hour = rate }
  end
end

# --- Sales orders ------------------------------------------------------------
# Required dates are relative to today so the order list always has overdue,
# this-week and later orders to show.
today = Date.current
[
  # [customer PO, customer, days from today, urgent, status, [[spec code, quantity kg], ...]]
  [ "M15159", "Brightform Packaging Ltd", -2, true, "open", [ [ "BF-700-250", 10_000 ] ] ],
  [ "P15745", "Brightform Packaging Ltd", 3, false, "open", [ [ "BF-650-300", 6_500 ], [ "BF-700-250", 4_000 ] ] ],
  [ "CT-88213", "Castleton Thermoforming", 5, false, "open", [ [ "CT-820-400", 12_000 ] ] ],
  [ "DBS-4410", "Delta Blister Solutions", 1, true, "open", [ [ "DB-560-200", 3_200 ] ] ],
  [ "FMT-0921", "Fenwick Medical Trays", 9, false, "open", [ [ "FM-600-350", 8_000 ] ] ],
  [ "GP-7781", "Greenway Punnets", 12, false, "open", [ [ "GP-750-275", 15_000 ] ] ],
  [ "KFP-3302", "Kestrel Food Packaging", 16, false, "open", [ [ "KF-900-450", 20_000 ], [ "STK-1000-500", 5_000 ] ] ],
  [ "LCP-118", "Lumen Cosmetics Packaging", 24, false, "open", [ [ "LC-500-180", 2_500 ] ] ],
  [ "OFC-5520", "Orchard Fresh Containers", 30, false, "open", [ [ "OF-700-250", 9_000 ] ] ],
  [ "PIT-207", "Pennine Industrial Trays", 7, false, "cancelled", [ [ "STK-1000-500", 4_000 ] ] ]
].each do |po, customer_name, days, urgent, status, lines|
  customer = customers.fetch(customer_name)
  order = SalesOrder.find_or_create_by!(customer: customer, customer_po_ref: po) do |o|
    o.required_on = today + days
    o.urgent = urgent
  end
  next unless order.lines.none?

  lines.each do |code, kg|
    # Prices per tonne in the customer's currency, so the Sage export has amounts.
    order.lines.create!(product_spec: ProductSpec.find_by!(code: code, revision: 1), quantity: kg.to_s,
                        price_per_tonne: (1_550 + code.sum % 300).to_s)
  end
  order.update!(status: status)
end

# --- Purchase orders -----------------------------------------------------------
# Dates are relative to today, so there's a draft, some sent POs (one overdue)
# and a cancelled one to show.
[
  # [supplier, days from today, status, supplier ref, [[material, quantity, unit, price per tonne], ...]]
  [ "Pacific Resin Exports", 21, "sent", "PRE-Q-2291", [ [ "JADE", "44", "t", "1,240.00" ] ] ],
  [ "EuroCap Polymers BV", -1, "sent", "OC-55102", [ [ "EuroCap Co-Ex", "11", "t", "1,610.00" ] ] ],
  [ "Circular Flake Co", 6, "sent", nil, [ [ "Clear PCW flake", "20", "t", "720.00" ] ] ],
  [ "Midlands Masterbatch", 9, "draft", nil, [ [ "Antiblock masterbatch", "1,000", "kg", "2,950.00" ], [ "Blue tint masterbatch", "250", "kg", "3,400.00" ] ] ],
  [ "Iberia Recycling SL", 14, "cancelled", "IR-0419", [ [ "Iberia PCW flake", "22", "t", "690.00" ] ] ]
].each do |supplier_name, days, status, ref, lines|
  supplier = Supplier.find_by!(name: supplier_name)
  next if PurchaseOrder.exists?(supplier:)

  order = PurchaseOrder.new(supplier:, supplier_ref: ref, expected_on: today + days)
  order.save_with_number || raise(order.errors.full_messages.to_sentence)
  lines.each do |material, quantity, unit, price|
    order.lines.create!(material: Material.find_by!(name: material), quantity_unit: unit, quantity:, price_per_tonne: price)
  end
  order.mark_sent! if status.in?(%w[ sent cancelled ])
  order.cancel! if status == "cancelled"
end

# --- Stock -------------------------------------------------------------------
# Opening stock and regrind (no PO), half a JADE delivery and part of a flake
# delivery. A few JADE bags are moved to storage and one bag is reweighed.
if Lot.none?
  Lot.transaction do
    admin = User.find_by(role: "admin")
    receive = ->(**attrs) { Stock::Receipt.new(**attrs).tap { _1.user = admin }.tap(&:save!).lots }

    receive.(material_id: Material.find_by!(name: "Albion Clear").id, quantity: "8.8", quantity_unit: "t", bags: 8,
             received_on: today - 30, supplier_lot_ref: "AC-2210", notes: "Opening stock")
    receive.(material_id: Material.find_by!(name: "EuroCap Co-Ex").id, quantity: "3,250", bags: 3,
             received_on: today - 30, supplier_lot_ref: "EC-7781", notes: "Opening stock")
    receive.(material_id: Material.find_by!(name: "Regrind chip").id, quantity: "2,960", bags: 4, received_on: today - 2)

    jade_line = PurchaseOrder.find_by!(supplier: Supplier.find_by!(name: "Pacific Resin Exports")).lines.sole
    jade = receive.(purchase_order_line: jade_line, quantity: "22", quantity_unit: "t", bags: 20, first_bag_no: "939",
                    supplier_lot_ref: "CZ302-26-118", delivery_ref: "DN-55120", received_on: today - 3)
    Stock::Transfer.call(jade.last(6), to: "storage", user: admin, note: "No room by the line")
    Stock::Adjustment.new(lot: jade.first, counted_kg: "1,092.5", reason: "Reweighed: torn bag").tap { _1.user = admin }.save!

    flake_line = PurchaseOrder.find_by!(supplier: Supplier.find_by!(name: "Circular Flake Co")).lines.sole
    receive.(purchase_order_line: flake_line, quantity: "9,860", bags: 10, supplier_lot_ref: "CF-0921",
             delivery_ref: "CF-DN-3312", received_on: today - 1)
  end
end

# --- Recipes -----------------------------------------------------------------
# One spec with its own recipe; the rest use the standard one (PLAN.md §11 Q6).
if SpecIngredient.none? && (spec = ProductSpec.find_by(code: "BF-700-250"))
  spec.recipe.update("virgin_coex" => "12", "virgin_mainex" => "48", "pcw" => "30", "regrind" => "10") || raise("recipe")
end

# --- Production plan ---------------------------------------------------------
# Both lines start at 06:00 today (UK time). Order lines are planned in
# required-date order, alternating lines; changeovers are added automatically.
# D1 also has a locked engineer visit the day after tomorrow.
if ScheduleBlock.none?
  start = Time.zone.parse("06:00", Date.current)
  d1, d2 = lines.fetch("D1"), lines.fetch("D2")
  editors = { d1 => Schedule::Editor.new(d1), d2 => Schedule::Editor.new(d2) }

  editors[d1].add(ScheduleBlock.new(kind: "planned_maintenance", duration_minutes: 240, locked: true,
                                     starts_at: start + 2.days + 8.hours, notes: "Engineer visit: screw inspection"))

  plannable = SalesOrderLine.joins(:sales_order).merge(SalesOrder.where(status: "open").by_required_date)
    .includes(product_spec: :line_rates).to_a
  plannable.first(8).each_with_index do |order_line, index|
    line = index.even? ? d1 : d2
    line = d1 unless order_line.product_spec.rate_for(d2) # e.g. specs that only run on D1
    first_on_line = line.schedule_blocks.where(locked: false).none?
    editors[line].add_job(order_line, starts_at: (start if first_on_line))
  end

  editors[d2].add(ScheduleBlock.new(kind: "no_orders", duration_minutes: 480, notes: "Nothing to run yet"))
end

# --- Production log ----------------------------------------------------------
# D1's first job is running as despatch 731 (carrying on from the paper logs),
# with the prestart checks done and a couple of width and thickness readings.
if ProductionRun.none? && (job = ProductionRun::Board.next_job_for(lines.fetch("D1")))
  admin = User.find_by(role: "admin")
  start = ProductionRun::Start.new(schedule_block: job, despatch_number: 731, started_at: job.starts_at.past? ? job.starts_at : Time.current.change(sec: 0),
                                   technician_days: "Dave Hirst", technician_nights: "Kev Shaw", antiblock_batch_no: "AB-5-2611")
  start.user = admin
  start.save || raise(start.errors.full_messages.to_sentence)
  run = start.run
  ProductionRun::Checklist.items("prestart").each_key { run.record_check(stage: "prestart", item: _1, passed: true, user: admin) }
  spec = run.product_spec
  run.record_measurement(stage: "startup", item: "width", actual: (spec.width_mm + 1).to_s, user: admin)
  run.record_measurement(stage: "startup", item: "thickness", actual: format(".%03d", spec.thickness_micron + 4), user: admin)

  # Seven reels so far, two to a pallet, spread between the start and now.
  weights = [ "1,042.5", "1,061", "1,055.5", "1,048", "1,066.5", "1,039", "1,052" ]
  step = (Time.current - run.started_at) / (weights.size + 1)
  weights.each_with_index do |weight_kg, index|
    run.reels.create!(weight_kg:, length_m: 5_620 + index * 7, pallet_no: index / 2 + 1, initials: index < 4 ? "DH" : "KS",
                      produced_at: run.started_at + step * (index + 1), user: admin)
  end

  # The bags on its feeds: JADE bag 939 ran out at reel 5 and bag 940 went on.
  first_lot = ->(material, **where) { Lot.joins(:material).where(materials: { name: material }, location: "on_site", **where).order(:code).first! }
  [
    [ first_lot.("EuroCap Co-Ex"), "virgin_coex", 1, "DH" ],
    [ first_lot.("JADE", bag_no: "939"), "virgin_mainex", 1, "DH" ],
    [ first_lot.("Clear PCW flake"), "pcw", 1, "DH" ],
    [ first_lot.("Regrind chip"), "regrind", 3, "DH" ],
    [ first_lot.("JADE", bag_no: "940"), "virgin_mainex", 5, "KS" ]
  ].each do |lot, feed, from_reel_no, initials|
    loading = ProductionRun::LoadMaterial.new(run: run.reload, lot_code: lot.code, feed:, from_reel_no:, initials:)
    loading.user = admin
    loading.save || raise(loading.errors.full_messages.to_sentence)
    loading.load.update_columns(loaded_at: run.reels.find_by(reel_no: from_reel_no)&.produced_at&.-(10.minutes) || run.started_at)
  end
end

# --- Dispatch ----------------------------------------------------------------
# Despatch 731's first two pallets went out this morning on DN-00001, which is
# waiting for the Sage export. Pallet 3 is ready for the next load.
if DeliveryNote.none? && (run = ProductionRun.find_by(despatch_number: 731))
  admin = User.find_by(role: "admin")
  order = run.sales_order
  note = order.delivery_notes.build(delivery_address: order.customer.address, haulier: "Pennine Haulage", vehicle_reg: "YX24 KLM")
  note.save_with_number || raise(note.errors.full_messages.to_sentence)
  note.set_pallets!([ [ run.id, 1 ], [ run.id, 2 ] ])
  note.mark_dispatched!(user: admin)
end

unless Rails.env.test?
  puts "Seeded #{User.count} users (password: #{demo_in_production ? "demo_password in credentials" : DEMO_PASSWORD}), #{Line.count} lines, #{Customer.count} customers, " \
       "#{Supplier.count} suppliers, #{Material.count} materials, #{ProductSpec.count} specs, #{SalesOrder.count} orders, #{PurchaseOrder.count} POs, #{Lot.count} lots, #{ScheduleBlock.count} plan blocks, #{ActionController::Base.helpers.pluralize(ProductionRun.count, "production log")}, #{ActionController::Base.helpers.pluralize(DeliveryNote.count, "delivery note")}"
end
