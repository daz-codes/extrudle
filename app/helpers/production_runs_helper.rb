module ProductionRunsHelper
  def production_home_path
    Current.user&.floor? ? floor_root_path : production_runs_path
  end

  def run_status_badge(run)
    run.running? ? tag.span("Running", class: "badge badge-lime") : tag.span("Finished", class: "badge badge-quiet")
  end

  # The header boxes of form 5.4.1.2, filled from the order and spec.
  def run_header_fields(run)
    spec, order, line = run.product_spec, run.sales_order, run.sales_order_line
    {
      "Customer" => order.customer.name,
      "Order" => [ order.number, order.customer_po_ref ].compact.join(" · "),
      "Spec" => spec.to_s,
      "Micron" => spec.paper_gauge,
      "Width" => mm(spec.width_mm),
      "Material" => spec.material_type.humanize,
      "PE" => yes_no(spec.pe),
      "Silicone" => silicone_summary(spec),
      "Antiblock" => yes_no(spec.antiblock),
      "Core" => "#{spec.core_inches}\" #{spec.core_orientation}",
      "Reel size" => reel_size_summary(spec),
      "Quantity" => order_quantity(line.quantity_g, unit: line.quantity_unit),
      "Required by" => l(order.required_on, format: "%a %-d %b %Y"),
      "Customer batch" => line.customer_batch_no
    }.compact
  end

  def pass_fail_badge(passed)
    if passed
      tag.span("Pass", class: "badge bg-ok-50 font-semibold text-ok-700")
    else
      tag.span("Fail", class: "badge bg-bad-50 font-semibold text-bad-700")
    end
  end

  # "697 mm (−3)" with the colour of the result.
  def reading(check)
    diff = check.difference
    delta = diff.zero? ? "on target" : "#{diff.positive? ? "+" : "−"}#{diff.abs}"
    tag.span(class: "font-mono font-semibold tabular-nums #{check.passed? ? "text-ok-700" : "text-bad-700"}") do
      "#{check.actual} #{check.unit} (#{delta})"
    end
  end

  def tolerance_text(item, spec)
    target, min, max = ProductionRun::Checklist.range(item, spec)
    unit = ProductionRun::Checklist.unit(item)
    "Target #{target} #{unit}, #{min}–#{max} #{unit} passes"
  end

  def checked_by(check)
    [ check.user&.name, l(check.checked_at, format: "%-d %b %H:%M") ].compact.join(", ")
  end
end
