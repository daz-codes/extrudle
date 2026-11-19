module StockHelper
  LOCATION_BADGES = {
    "on_site" => "badge-lime",
    "storage" => "badge-quiet",
    "at_supplier" => "badge-lemon",
    "in_transit" => "badge-lemon"
  }.freeze

  def location_badge(location)
    tag.span(Lot.location_label(location), class: "badge #{LOCATION_BADGES.fetch(location.to_s)}")
  end

  # Exact stock weight: "12.345 t" from a tonne up, else "750 kg". Blank for zero.
  def stock_weight(grams, blank: "—")
    grams.to_i.zero? ? blank : order_quantity(grams)
  end

  MOVEMENT_LABELS = {
    "receipt" => "Received",
    "transfer" => "Moved",
    "issue_to_production" => "Used in production",
    "adjustment" => "Adjusted"
  }.freeze

  def movement_summary(movement)
    case movement.kind
    when "transfer" then "Moved from #{Lot.location_label(movement.from_location).downcase} to #{Lot.location_label(movement.to_location).downcase}"
    when "receipt" then "Received into #{Lot.location_label(movement.to_location).downcase}"
    when "issue_to_production"
      run = movement.production_run
      safe_join([ "Used by ", link_to("despatch #{run.despatch_number}", production_run_material_loads_path(run), class: "link") ])
    else MOVEMENT_LABELS.fetch(movement.kind)
    end
  end

  def signed_weight(grams)
    return "—" if grams.zero?

    "#{grams.positive? ? "+" : "−"}#{Weight.format_kg(grams.abs)}"
  end

  # Inline SVG QR code of a lot code (just the code: the app looks up the rest).
  def lot_qr_svg(lot)
    RQRCode::QRCode.new(lot.code).as_svg(module_size: 4, use_path: true, viewbox: true, svg_attributes: { class: "size-full", role: "img", "aria-label": "QR code for #{lot.code}" }).html_safe # rubocop:disable Rails/OutputSafety
  end
end
