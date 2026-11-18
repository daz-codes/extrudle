module PlannerHelper
  # Timeline colours by kind. Urgent jobs are lemon; late ones get a red edge.
  def block_classes(block, warnings = [])
    base = case block.kind
    when "job" then block.sales_order&.urgent? ? "bg-lemon-300 text-ink-900" : "bg-lime-200 text-ink-900"
    when "changeover" then "bg-ink-200 text-ink-700 block-hatched"
    when "planned_maintenance" then "bg-ink-800 text-white"
    when "unplanned_maintenance" then "bg-bad-50 text-bad-800 ring-1 ring-inset ring-bad-600"
    else "bg-surface text-ink-500 ring-1 ring-inset ring-ink-300 block-hatched"
    end
    late = warnings.any? { _1.code == :late } ? "ring-2 ring-inset ring-bad-600" : nil
    [ base, late ].compact.join(" ")
  end

  def block_title(block)
    if block.job?
      "#{block.sales_order.number} · #{block.product_spec}"
    else
      block.kind.humanize
    end
  end

  def block_subtitle(block)
    if block.job?
      "#{block.sales_order.customer.name} · #{kg(block.planned_g)}"
    else
      block.notes.presence || (block.automatic? ? "Automatic, between specs" : nil)
    end
  end

  def duration_text(minutes) = Schedule.duration_text(minutes)

  def plan_time(time)
    l(time, format: "%a %-d %b %H:%M")
  end

  # The end time, with the day only when it's not the start day.
  def plan_finish(block)
    block.starts_at.to_date == block.ends_at.to_date ? l(block.ends_at, format: "%H:%M") : plan_time(block.ends_at)
  end

  def plan_range(block)
    "#{plan_time(block.starts_at)} – #{plan_finish(block)}"
  end

  def hours_value(minutes)
    DecimalInput.from_scaled_integer(minutes, 60)
  end

  def datetime_local_value(time)
    time&.strftime("%Y-%m-%dT%H:%M")
  end

  def lock_icon
    tag.svg(viewBox: "0 0 16 16", class: "inline size-3.5 shrink-0", aria: { hidden: true }, fill: "currentColor") do
      tag.path(d: "M5 7V5a3 3 0 1 1 6 0v2h.5A1.5 1.5 0 0 1 13 8.5v5a1.5 1.5 0 0 1-1.5 1.5h-7A1.5 1.5 0 0 1 3 13.5v-5A1.5 1.5 0 0 1 4.5 7H5Zm1.5 0h3V5a1.5 1.5 0 1 0-3 0v2Z")
    end
  end

  # Default start for the first block on an empty line: the next 06:00.
  def default_queue_start
    six = Time.zone.parse("06:00")
    six > Time.current ? six : six + 1.day
  end
end
