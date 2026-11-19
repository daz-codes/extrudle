module PurchaseOrdersHelper
  PO_STATUS_BADGES = {
    "draft" => "badge-quiet",
    "sent" => "badge-lime",
    "part_received" => "badge-lemon",
    "received" => "bg-ok-50 text-ok-700",
    "cancelled" => "bg-bad-50 text-bad-700"
  }.freeze

  def po_status_badge(order)
    tag.span(order.status.humanize, class: "badge #{PO_STATUS_BADGES.fetch(order.status)}")
  end

  def expected_date(order)
    text = l(order.expected_on, format: "%a %-d %b %Y")
    order.overdue? ? tag.span("#{text} · overdue", class: "font-semibold text-bad-700") : text
  end

  # Materials a PO line can use: the supplier's own materials first, then any
  # other bought-in material (Working assumption, see PLAN.md §11 Q23).
  def material_options_for(order, selected_id = nil)
    scope = Material.purchased.active.or(Material.where(id: selected_id)).includes(:supplier).by_name
    own, other = scope.partition { _1.supplier_id == order.supplier_id }
    groups = []
    groups << [ "#{order.supplier.name} materials", own.map { [ _1.to_s, _1.id ] } ] if own.any?
    groups << [ "Other materials", other.map { [ material_option_label(_1), _1.id ] } ] if other.any?
    grouped_options_for_select(groups, selected_id)
  end

  def material_option_label(material)
    [ material.to_s, material.supplier&.name ].compact.join(" · ")
  end

  def incoterm_options
    Currency::INCOTERMS
  end
end
