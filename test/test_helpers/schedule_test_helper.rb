module ScheduleTestHelper
  MONDAY_6AM = "2026-11-16 06:00"

  def at(text)
    Time.zone.parse(text)
  end

  # An order for Rhine on the stock spec (which has no line rates), for changeover and no-rate tests.
  def stock_order_line(kg: 1_000, required_on: Date.new(2026, 11, 30))
    order = SalesOrder.create!(customer: customers(:rhine), required_on: required_on)
    order.lines.create!(product_spec: product_specs(:stock), quantity: kg.to_s)
  end

  def block(kind, minutes, **attrs)
    ScheduleBlock.new(kind: kind, duration_minutes: minutes, **attrs)
  end

  def timeline(line)
    line.schedule_blocks.reload.ordered.map { |b| [ b.kind, b.starts_at.strftime("%a %H:%M"), b.ends_at.strftime("%a %H:%M") ] }
  end
end
