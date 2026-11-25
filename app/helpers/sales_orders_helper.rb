module SalesOrdersHelper
  ORDER_STATUS_BADGES = {
    "open" => "badge-quiet",
    "scheduled" => "badge-lime",
    "in_production" => "badge-lime",
    "dispatched" => "bg-ok-50 text-ok-700",
    "invoiced" => "bg-ok-50 text-ok-700",
    "cancelled" => "bg-bad-50 text-bad-700"
  }.freeze

  def order_status_badge(order)
    tag.span(order.status.humanize, class: "badge #{ORDER_STATUS_BADGES.fetch(order.status)}")
  end

  # "Mon 30 Nov 2026", or "w/c Mon 30 Nov 2026" for a week order (§11 Q90).
  def required_on_text(order, format: "%a %-d %b %Y")
    text = l(order.required_on, format:)
    order.required_week? ? "w/c #{text}" : text
  end

  def required_date(order)
    text = required_on_text(order)
    if order.late?
      tag.span(class: "font-semibold text-bad-700") { "#{text} · late" }
    else
      text
    end
  end

  def urgent_badge(order)
    tag.span("Urgent", class: "badge badge-lemon") if order.urgent?
  end

  # Specs a line on this order can use: the customer's own specs, then stock specs.
  def spec_options_for(order, selected_id = nil)
    scope = ProductSpec.active.or(ProductSpec.where(id: selected_id)).by_code
    own = scope.where(customer_id: order.customer_id).map { |spec| [ spec_option_label(spec), spec.id ] }
    stock = scope.where(customer_id: nil).map { |spec| [ spec_option_label(spec), spec.id ] }
    groups = []
    groups << [ "#{order.customer.name} specs", own ] if own.any?
    groups << [ "Stock specs", stock ] if stock.any?
    grouped_options_for_select(groups, selected_id)
  end

  def spec_option_label(spec)
    "#{spec} · #{spec.thickness_micron} µm × #{spec.width_mm} mm"
  end

  # Exact, never rounded: "12.345 t", "750 kg". A line shows the unit it was entered in;
  # totals use tonnes from 1 t up.
  def order_quantity(grams, unit: nil)
    unit ||= grams >= Weight::GRAMS_PER_TONNE ? "t" : "kg"
    number = DecimalInput.from_scaled_integer(grams, EnteredQuantity::UNITS.fetch(unit))
    "#{number_with_delimiter(number)} #{unit}"
  end
end
