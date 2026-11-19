# One production log (paper form 5.4.1.2), identified by its despatch number.
# Started from a planned job with ProductionRun::Start. The spec revision and
# order line are kept as they were when the run started.
class ProductionRun < ApplicationRecord
  belongs_to :line
  belongs_to :schedule_block, optional: true
  belongs_to :sales_order_line
  belongs_to :product_spec
  belongs_to :started_by, class_name: "User", optional: true
  belongs_to :finished_by, class_name: "User", optional: true
  has_many :reels, -> { order(:reel_no) }, inverse_of: :production_run, dependent: :restrict_with_error
  has_many :checks, -> { order(:checked_at, :id) }, class_name: "RunCheck", inverse_of: :production_run, dependent: :destroy
  has_many :delivery_note_pallets, dependent: :restrict_with_error
  has_many :material_loads, -> { order(:from_reel_no, :loaded_at, :id) }, inverse_of: :production_run, dependent: :restrict_with_error
  has_many :consumptions, -> { issue_to_production }, class_name: "StockMovement", inverse_of: :production_run, dependent: :restrict_with_error

  # Raised by finish! with the reasons the log can't be finished yet.
  class NotFinishable < StandardError; end

  # finished is set by finish! on the end-of-run screen.
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

  def measurements(item, stage: "startup")
    checks.select { _1.measurement? && _1.stage == stage.to_s && _1.item == item.to_s }
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

  # Reels -------------------------------------------------------------------

  def total_g = reels.sum(&:weight_g)

  def order_quantity_g = sales_order_line.quantity_g

  # Whole percent of the order line made so far, rounded down (integer maths).
  # Working assumption, see PLAN.md §11 Q45.
  def percent_of_order
    order_quantity_g.positive? ? total_g * 100 / order_quantity_g : 0
  end

  def next_reel_no = (reels.filter_map(&:reel_no).max || 0) + 1

  # The pallet the next reel goes on: the last reel's pallet until it holds the
  # spec's reels per pallet, then the next one. One reel per pallet when the
  # spec doesn't say. Working assumption, see PLAN.md §11 Q42.
  def suggested_pallet_no
    last_pallet = reels.filter_map(&:pallet_no).max
    return 1 if last_pallet.nil?
    return last_pallet + 1 if pallet_on_delivery_note?(last_pallet)

    per_pallet = product_spec.reels_per_pallet || 1
    reels.count { _1.pallet_no == last_pallet } < per_pallet ? last_pallet : last_pallet + 1
  end

  # A new reel with the number, pallet and initials filled in for a fast entry.
  # Built by id, not through reels, so it stays out of the totals until saved.
  def build_next_reel(**attributes)
    Reel.new(production_run_id: id, reel_no: next_reel_no, pallet_no: suggested_pallet_no, initials: reels.last&.initials, **attributes)
  end

  # Pallets ----------------------------------------------------------------

  def pallets = Pallet.for_run(self)

  # Pallets that have gone on a delivery note can't take more reels.
  def pallet_on_delivery_note?(pallet_no)
    pallet_no.present? && delivery_note_pallets.any? { _1.pallet_no == pallet_no }
  end

  # The delivery notes its pallets went out on ("No. of deliveries" on the log).
  def delivery_notes
    DeliveryNote.where(id: delivery_note_pallets.select(:delivery_note_id)).order(:number)
  end

  # Finishing ---------------------------------------------------------------

  def line_clearance_complete?
    Checklist.items("line_clearance").keys.all? { answer("line_clearance", _1)&.passed? }
  end

  # What still stops the log being finished, as messages for the technician.
  # Working assumption, see PLAN.md §11 Q41.
  def finish_problems
    problems = []
    problems << "Enter at least one reel" if reels.empty?
    problems << "Record the material bags loaded" if material_loads.empty?
    Checklist::MEASUREMENTS.each do |item, info|
      problems << "Record the end-of-run #{info[:label].downcase}" if measurements(item, stage: "end_of_run").empty?
    end
    Checklist.items("line_clearance").each do |item, label|
      problems << "Line clearance: #{label.downcase_first}" unless answer("line_clearance", item)&.passed?
    end
    if out_of_tolerance_at_end? && comments.blank?
      problems << "An end-of-run reading is out of tolerance: add a comment or corrective action"
    end
    problems
  end

  def out_of_tolerance_at_end?
    Checklist::MEASUREMENTS.keys.any? { measurements(_1, stage: "end_of_run").last&.passed? == false }
  end

  def finish!(user: nil, ended_at: Time.current)
    raise NotFinishable, "Despatch #{despatch_number} is already finished" unless running?

    problems = finish_problems
    raise NotFinishable, problems.to_sentence if problems.any?

    transaction do
      update!(status: "finished", ended_at:, finished_by: user)
      material_use.post!(user:)
      material_loads.map(&:lot).uniq.each { Stock::Reconciliation.call(_1, user:) }
    end
  end

  # Materials ---------------------------------------------------------------

  # The bag on each feed now: { feed => MaterialLoad }, the latest load per feed.
  def current_loads
    material_loads.group_by(&:feed).transform_values(&:last)
  end

  # The reels a load fed, as a range for the log ("1–5"). The end is open
  # while the bag is still on a running log. Nil if the next bag went on first.
  def reel_range(load)
    loads = material_loads.select { _1.feed == load.feed }
    following = loads[loads.index(load) + 1]
    last = following ? following.from_reel_no - 1 : (reels.filter_map(&:reel_no).max if finished?)
    return (load.from_reel_no..) if last.nil?

    load.from_reel_no..last if last >= load.from_reel_no
  end

  # What the run used from each bag (estimated while running, posted on finish).
  def material_use = MaterialUse.new(self)

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
