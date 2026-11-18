class ScheduleBlock < ApplicationRecord
  include ScaledAttributes

  belongs_to :line
  belongs_to :sales_order_line, optional: true

  enum :kind, {
    job: "job",
    changeover: "changeover",
    planned_maintenance: "planned_maintenance",
    unplanned_maintenance: "unplanned_maintenance",
    no_orders: "no_orders"
  }, validate: true

  scaled_attribute :planned_kg, column: :planned_g, scale: Weight::GRAMS_PER_KG

  # Sort key used while editing a queue (fractional positions for inserts). Not stored.
  attr_accessor :queue_key

  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0 }
  validate :duration_in_whole_slots
  validates :starts_at, :ends_at, presence: true
  validate :times_on_slots_and_consistent
  validates :sales_order_line, presence: true, if: :job?
  validates :planned_g, numericality: { only_integer: true, greater_than: 0 }, if: :job?
  validates :sales_order_line, :planned_g, absence: true, unless: :job?
  validates :automatic, absence: { message: "is only for unlocked changeovers" }, unless: -> { changeover? && !locked? }
  validate :locked_blocks_do_not_overlap, if: :locked?

  scope :ordered, -> { order(:starts_at, :position) }
  scope :jobs, -> { where(kind: "job") }

  delegate :product_spec, to: :sales_order_line, allow_nil: true
  delegate :sales_order, to: :sales_order_line, allow_nil: true

  def line_rate
    return unless job? && product_spec

    product_spec.line_rates.detect { _1.line_id == line_id }
  end

  # For jobs with a rate, the duration comes from planned weight ÷ rate.
  # Jobs without a rate keep their manual duration (and get a warning).
  def calculated_duration_minutes
    rate = line_rate
    rate ? Schedule.job_minutes(planned_g, rate.kg_per_hour) : duration_minutes
  end

  def refresh_duration
    self.duration_minutes = calculated_duration_minutes if job? && planned_g.to_i.positive?
  end

  def place_at(start)
    self.starts_at = start
    self.ends_at = start + duration_minutes.minutes
  end

  def to_s
    job? ? "#{sales_order.number} #{product_spec}" : kind.humanize
  end

  private
    def duration_in_whole_slots
      return if duration_minutes.blank?

      errors.add(:duration_minutes, "must be a multiple of #{Schedule::SLOT_MINUTES} minutes") unless (duration_minutes % Schedule::SLOT_MINUTES).zero?
    end

    def times_on_slots_and_consistent
      return if starts_at.blank? || ends_at.blank? || duration_minutes.blank?

      errors.add(:starts_at, "must be on a 30-minute boundary") unless Schedule.on_slot?(starts_at)
      errors.add(:ends_at, "must match the duration") unless ends_at == starts_at + duration_minutes.minutes
    end

    def locked_blocks_do_not_overlap
      return if starts_at.blank? || ends_at.blank?

      clash = line.schedule_blocks.where(locked: true).where.not(id: id)
        .where("starts_at < ? AND ends_at > ?", ends_at, starts_at).first
      errors.add(:starts_at, "overlaps the locked #{clash.kind.humanize.downcase} at #{I18n.l(clash.starts_at, format: '%a %-d %b %H:%M')}") if clash
    end
end
