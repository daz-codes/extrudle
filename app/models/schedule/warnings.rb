# Problems the planner should see on each block (PLAN.md §3).
#
#   warnings = Schedule::Warnings.for_line(line)
#   warnings[block] #=> [#<Warning code=:late ...>]
class Schedule::Warnings
  Warning = Data.define(:code, :message)

  # plan: the live plan or a draft; "over planned" counts that plan's jobs.
  def self.for_line(line, blocks = nil, plan: Schedule::Plan.live)
    blocks ||= plan.blocks_for(line).ordered.includes(sales_order_line: [ :sales_order, { product_spec: :line_rates } ]).to_a
    new(line, blocks, plan:).to_h
  end

  def initialize(line, blocks, plan: Schedule::Plan.live)
    @line = line
    @blocks = blocks.sort_by { [ _1.starts_at, _1.position ] }
    @plan = plan
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
      return if block.kg_per_hour

      Warning.new(:no_rate, "Line #{@line.name} has no rate for #{block.product_spec}, so #{duration(block.duration_minutes)} is an estimate")
    end

    # "Late" means finishing after the end of the required day, or a week
    # order's Friday, UK time (§11 Q16, Q90).
    def late(block)
      order = block.sales_order
      return unless block.ends_at > order.deadline

      required = order.required_week? ? "w/c #{I18n.l(order.required_on, format: '%a %-d %b')}" : I18n.l(order.required_on, format: "%a %-d %b")
      Warning.new(:late, "Finishes #{I18n.l(block.ends_at, format: '%a %-d %b %H:%M')}, after #{order.number}'s required date (#{required})")
    end

    def over_planned(block)
      order_line = block.sales_order_line
      planned = @plan.planned_g(order_line)
      return unless planned > order_line.quantity_g

      Warning.new(:over_planned, "#{Weight.format_kg(planned)} planned for #{order_line.sales_order.number} #{order_line.product_spec}, " \
                                 "but #{Weight.format_kg(order_line.quantity_g)} is ordered")
    end

    def idle_before(block, previous)
      minutes = ((block.starts_at - previous.ends_at) / 60).to_i
      Warning.new(:idle, "Line #{@line.name} is idle for #{duration(minutes)} before this #{block.kind.humanize.downcase}")
    end

    def duration(minutes) = Schedule.duration_text(minutes)
end
