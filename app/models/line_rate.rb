class LineRate < ApplicationRecord
  belongs_to :line
  belongs_to :product_spec

  validates :kg_per_hour, numericality: { only_integer: true, greater_than: 0 }
  validates :line_id, uniqueness: { scope: :product_spec_id }

  # Job durations come from rates, so a new rate re-times any planned jobs for this spec.
  # Runs inside the save's transaction, through Schedule::Editor: if the new times
  # don't fit (e.g. a locked job would overlap another locked block), the rate isn't saved.
  after_save :reflow_planned_jobs, if: :saved_change_to_kg_per_hour?

  private
    def reflow_planned_jobs
      planned = line.schedule_blocks.jobs.joins(:sales_order_line).where(sales_order_lines: { product_spec_id: product_spec_id })
      Schedule::Editor.new(line).reflow if planned.exists?
    rescue Schedule::Error => e
      errors.add(:base, "This rate would clash with the plan on line #{line.name}: #{e.message}")
      raise ActiveRecord::RecordInvalid, self
    end
end
