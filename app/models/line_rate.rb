class LineRate < ApplicationRecord
  belongs_to :line
  belongs_to :product_spec

  validates :kg_per_hour, numericality: { only_integer: true, greater_than: 0 }
  validates :line_id, uniqueness: { scope: :product_spec_id }

  # Job durations come from rates, so a new rate re-times any planned jobs for this spec.
  after_commit :reflow_planned_jobs

  private
    def reflow_planned_jobs
      planned = line.schedule_blocks.jobs.joins(:sales_order_line).where(sales_order_lines: { product_spec_id: product_spec_id })
      Schedule::Reflow.new(line).call if planned.exists?
    end
end
