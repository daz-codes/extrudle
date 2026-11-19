# Starts a production log from a planned job. Takes the next despatch number
# (or the one typed in), keeps the job's order line and spec revision, copies
# the spec's packaging notes and the order notes into the special instructions,
# and puts the order "in production". Bags still on the line's feeds carry over.
#
# Working assumption, see PLAN.md §11 Q38: starting a run doesn't change the
# plan. The planner re-times the line if the job starts early or late.
class ProductionRun::Start
  include ActiveModel::Model
  include ActiveModel::Attributes

  attribute :despatch_number, :integer, default: -> { ProductionRun.next_despatch_number }
  attribute :started_at, :datetime, default: -> { Time.current.change(sec: 0) }
  attribute :technician_days, :string
  attribute :technician_nights, :string
  attribute :antiblock_batch_no, :string
  attribute :silicone_batch_no, :string
  attribute :pe_film_batch_no, :string

  attr_reader :schedule_block, :run
  attr_accessor :user

  validates :despatch_number, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :started_at, presence: true
  validate :block_is_a_job_without_a_log
  validate :order_can_be_made
  validate :not_in_the_future

  def initialize(schedule_block:, **attributes)
    @schedule_block = schedule_block
    super(**attributes)
  end

  # The form sends UK local time ("2026-07-01T06:00"); read it in Europe/London, not UTC.
  def started_at=(value)
    super(value.is_a?(String) && value.present? ? Time.zone.parse(value) : value)
  end

  delegate :line, :sales_order_line, :product_spec, :sales_order, to: :schedule_block

  def save
    return false unless valid?

    ProductionRun.transaction do
      @run = ProductionRun.new(
        line:, schedule_block:, sales_order_line:, product_spec:, started_by: user, despatch_number:, started_at:,
        technician_days:, technician_nights:, antiblock_batch_no:, silicone_batch_no:, pe_film_batch_no:,
        special_instructions: [ product_spec.packaging_notes, sales_order.notes ].compact_blank.join("\n").presence
      )
      unless @run.save
        @run.errors.each { |error| errors.import(error) }
        raise ActiveRecord::Rollback
      end
      sales_order.in_production! if sales_order.editable?
      carry_over_bags
    end
    errors.empty?
  rescue ActiveRecord::RecordNotUnique => e
    # Two people starting at once: say which unique index was hit.
    if e.message.include?("schedule_block_id")
      errors.add(:base, "This job already has a production log")
    elsif e.message.include?("line_id")
      errors.add(:base, "Line #{line.name} is already running another log. Finish that log first.")
    else
      errors.add(:despatch_number, :taken)
    end
    false
  end

  private
    # Bags still on the feeds when the line's last log finished carry on
    # feeding this one from reel 1. Working assumption, see PLAN.md §11 Q47.
    def carry_over_bags
      previous = ProductionRun.finished.where(line:).where.not(id: @run.id).order(ended_at: :desc, id: :desc).first
      return unless previous

      previous.current_loads.each_value do |load|
        next if load.lot.emptied?

        @run.material_loads.create!(lot: load.lot, feed: load.feed, from_reel_no: 1, carried_over: true,
                                    loaded_at: started_at, initials: load.initials, user:)
      end
    end

    def block_is_a_job_without_a_log
      if !schedule_block&.job?
        errors.add(:base, "Only planned jobs can be started")
      elsif ProductionRun.exists?(schedule_block:)
        errors.add(:base, "This job already has a production log")
      end
    end

    def order_can_be_made
      return unless schedule_block&.job?
      return if SalesOrder::ACTIVE_STATUSES.include?(sales_order.status)

      errors.add(:base, "Order #{sales_order.number} is #{sales_order.status.humanize.downcase}")
    end

    def not_in_the_future
      errors.add(:started_at, "can't be in the future") if started_at && started_at > 5.minutes.from_now
    end
end
