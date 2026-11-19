# One production log (paper form 5.4.1.2), identified by its despatch number.
# Started from a planned job with ProductionRun::Start. The spec revision and
# order line are kept as they were when the run started.
class ProductionRun < ApplicationRecord
  belongs_to :line
  belongs_to :schedule_block, optional: true
  belongs_to :sales_order_line
  belongs_to :product_spec
  belongs_to :started_by, class_name: "User", optional: true
  has_many :checks, -> { order(:checked_at, :id) }, class_name: "RunCheck", inverse_of: :production_run, dependent: :destroy

  # finished is set by the end-of-run screen (Slice 7b).
  enum :status, { running: "running", finished: "finished" }, default: :running, validate: true

  normalizes :antiblock_batch_no, :silicone_batch_no, :pe_film_batch_no, :technician_days, :technician_nights,
             with: ->(text) { text.squish.presence }

  validates :despatch_number, presence: true, uniqueness: true, numericality: { only_integer: true, greater_than: 0 }
  validates :started_at, presence: true
  validate :one_running_log_per_line, if: :running?

  delegate :sales_order, to: :sales_order_line
  delegate :customer, to: :sales_order

  scope :recent_first, -> { order(started_at: :desc, despatch_number: :desc) }

  # Carries on from the highest despatch number so far. Working assumption,
  # see PLAN.md §11 Q33: the first number can be typed in when starting a run.
  def self.next_despatch_number
    maximum(:despatch_number).to_i + 1
  end

  def editable? = running?

  # The latest answer for a yes/no check, or nil if not answered yet.
  def answer(stage, item)
    checks.select { _1.stage == stage.to_s && _1.item == item.to_s }.last
  end

  def measurements(item)
    checks.select { _1.measurement? && _1.item == item.to_s }
  end

  def prestart_complete?
    Checklist.items("prestart").keys.all? { answer("prestart", _1)&.passed? }
  end

# Records a yes/no answer. A later answer replaces an earlier one on screen,
# but both are kept for the record.
def record_check(stage:, item:, passed:, user: nil, note: nil)
  checks.create(stage:, item:, passed: ActiveModel::Type::Boolean.new.cast(passed), user:, note: note.presence)
end

# Records a width or thickness reading, judged against the spec's target and
# tolerance. Thickness can be typed in microns ("252") or as on the paper
# plan (".252" or "0.252" mm).
def record_measurement(stage:, item:, actual:, user: nil, note: nil)
  check = checks.build(stage:, item:, user:, note: note.presence)
  if ProductionRun::Checklist.measurement?(stage, item)
    check.target, check.min_value, check.max_value = ProductionRun::Checklist.range(item, product_spec)
    check.unit = ProductionRun::Checklist.unit(item)
    check.actual = RunCheck.parse_reading(item, actual)
  end
  check.save
  check
rescue ArgumentError => e
  check.errors.add(:actual, e.message)
  checks.delete(check)
  check
end

  def to_s = "Despatch #{despatch_number}"

  private
    # Working assumption, see PLAN.md §11 Q34: one log at a time per line.
    def one_running_log_per_line
      others = ProductionRun.running.where(line_id:).where.not(id:)
      if (other = others.first)
        errors.add(:base, "Line #{line.name} is already running despatch #{other.despatch_number}. Finish that log first.")
      end
    end
end
