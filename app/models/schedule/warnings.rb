# Problems the planner should see on each block (PLAN.md §3).
#
#   warnings = Schedule::Warnings.for_line(line)
#   warnings[block] #=> [#<Warning code=:late ...>]
class Schedule::Warnings
  Warning = Data.define(:code, :message)

  def self.for_line(line, blocks = nil)
    blocks ||= line.schedule_blocks.ordered.includes(sales_order_line: [ :sales_order, :schedule_blocks, { product_spec: :line_rates } ]).to_a
    new(line, blocks).to_h
  end

  def initialize(line, blocks)
    @line = line
    @blocks = blocks.sort_by { [ _1.starts_at, _1.position ] }
  end

  def to_h
    previous = nil
    @blocks.each_with_object({}) do |block, warnings|
      list = []
      list.concat(job_warnings(block)) if block.job?
      list << idle_before(block, previous) if previous && block.locked? && block.starts_at > previous.ends_at
      warnings[block] = list.compact
      previous = block
    end
  end

  private
    def job_warnings(block)
      [ no_rate(block), late(block), over_planned(block) ]
    end

    def no_rate(block)
      return if block.line_rate

      Warning.new(:no_rate, "Line #{@line.name} has no rate for #{block.product_spec}, so #{duration(block.duration_minutes)} is an estimate")
    end

    # "Late" means finishing after the end of the required day, UK time (§11 Q16).
    def late(block)
      order = block.sales_order
      deadline = order.required_on.end_of_day
      return unless block.ends_at > deadline

      Warning.new(:late, "Finishes #{I18n.l(block.ends_at, format: '%a %-d %b %H:%M')}, after #{order.number}'s required date (#{I18n.l(order.required_on, format: '%a %-d %b')})")
    end

    def over_planned(block)
      order_line = block.sales_order_line
      planned = order_line.planned_g
      return unless planned > order_line.quantity_g

      Warning.new(:over_planned, "#{Weight.format_kg(planned)} planned for #{order_line.sales_order.number} #{order_line.product_spec}, " \
                                 "but #{Weight.format_kg(order_line.quantity_g)} is ordered")
    end

    def idle_before(block, previous)
      minutes = ((block.starts_at - previous.ends_at) / 60).to_i
      Warning.new(:idle, "Line #{@line.name} is idle for #{duration(minutes)} before this #{block.kind.humanize.downcase}")
    end

    def duration(minutes)
      hours, mins = minutes.divmod(60)
      [ ("#{hours}h" if hours.positive?), ("#{mins}m" if mins.positive?) ].compact.join(" ").presence || "0m"
    end
end
