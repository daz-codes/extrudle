# What each line is doing: its running log, or the next planned job to start.
class ProductionRun::Board
  Entry = Data.define(:line, :run, :next_job)

  def entries
    @entries ||= begin
      lines = Line.active.order(:position, :name).to_a
      running = ProductionRun.running.where(line: lines)
        .includes(:product_spec, :reels, sales_order_line: { sales_order: :customer }).index_by(&:line_id)
      lines.map { |line| Entry.new(line:, run: running[line.id], next_job: running[line.id] ? nil : self.class.next_job_for(line)) }
    end
  end

  # The earliest planned job on the line that hasn't been started, for an order still to make.
  def self.next_job_for(line)
    ScheduleBlock.live.jobs.where(line:).where.missing(:production_run)
      .joins(sales_order_line: :sales_order).merge(SalesOrder.active)
      .includes(sales_order_line: [ :product_spec, { sales_order: :customer } ]).order(:starts_at).first
  end
end
