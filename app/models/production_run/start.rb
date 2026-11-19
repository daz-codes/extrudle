# Starts a production log from a planned job. Takes the next despatch number
# (or the one typed in), keeps the job's order line and spec revision, copies
# the spec's packaging notes and the order notes into the special instructions,
# and puts the order "in production".
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
    end
    errors.empty?
  rescue ActiveRecord::RecordNotUnique
    errors.add(:despatch_number, :taken)
    false
  end

  private
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
