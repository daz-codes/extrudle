# Demo data. Idempotent: safe to run more than once (bin/rails db:seed).
# All company names are fictional.

DEMO_PASSWORD = "extrudle-demo"

[
  { name: "Stu Admin",     email_address: "admin@extrudle.test",  role: "admin" },
  { name: "Olivia Office", email_address: "office@extrudle.test", role: "office" },
  { name: "Fred Floor",    email_address: "floor@extrudle.test",  role: "floor" }
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
  [ "Brightform Packaging Ltd", "Hannah Cole", "GBP" ],
  [ "Castleton Thermoforming", "Raj Patel", "GBP" ],
  [ "Delta Blister Solutions", "Mark Ellis", "GBP" ],
  [ "Fenwick Medical Trays", "Sarah Odum", "GBP" ],
  [ "Greenway Punnets", "Tom Hirst", "GBP" ],
  [ "Harbour Point Displays", "Lucy Barnes", "GBP" ],
  [ "Kestrel Food Packaging", "Ian McLeod", "GBP" ],
  [ "Lumen Cosmetics Packaging", "Amira Shah", "EUR" ],
  [ "Northgate Clamshells", "Dan Price", "GBP" ],
  [ "Orchard Fresh Containers", "Megan Lloyd", "GBP" ],
  [ "Pennine Industrial Trays", "Chris Walsh", "GBP" ],
  [ "Rhine Valley Verpackung GmbH", "Jonas Weber", "EUR" ]
].to_h do |name, contact, currency|
  [ name, Customer.find_or_create_by!(name: name) { _1.assign_attributes(contact_name: contact, currency: currency) } ]
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

unless Rails.env.test?
  puts "Seeded #{User.count} users (password: #{DEMO_PASSWORD}), #{Line.count} lines, #{Customer.count} customers, " \
       "#{Supplier.count} suppliers, #{Material.count} materials, #{ProductSpec.count} specs"
end
