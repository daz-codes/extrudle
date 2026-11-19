class SalesOrder < ApplicationRecord
  include SequentialNumber
  numbered_with "SO" # Working assumption, see PLAN.md §11 Q11.

  belongs_to :customer
  has_many :lines, -> { order(:id) }, class_name: "SalesOrderLine", inverse_of: :sales_order, dependent: :destroy

  # scheduled, in_production, dispatched and invoiced are set by later slices
  # (planner, production log, dispatch). Slice 2 only cancels and reopens.
  enum :status, {
    open: "open", scheduled: "scheduled", in_production: "in_production",
    dispatched: "dispatched", invoiced: "invoiced", cancelled: "cancelled"
  }, default: :open, validate: true

  ACTIVE_STATUSES = %w[ open scheduled in_production ].freeze
  EDITABLE_STATUSES = %w[ open scheduled ].freeze

  normalizes :customer_po_ref, with: ->(ref) { ref.strip.upcase.presence }

  validates :required_on, presence: true
  validate :customer_is_active, if: -> { new_record? || will_save_change_to_customer_id? }
  validate :customer_fixed_once_lines_exist, on: :update

  scope :active, -> { where(status: ACTIVE_STATUSES) }
  scope :by_required_date, -> { order(required_on: :asc, urgent: :desc, number: :asc) }
  scope :search, ->(q) {
    next all if q.blank?
    like = "%#{sanitize_sql_like(q)}%"
    left_joins(:customer).where("sales_orders.number LIKE :q OR sales_orders.customer_po_ref LIKE :q OR customers.name LIKE :q", q: like)
  }

  # Date windows for the order list, relative to today (Europe/London).
  WINDOWS = {
    "overdue" => "Overdue",
    "this_week" => "This week",
    "next_two_weeks" => "Next 2 weeks",
    "later" => "Later"
  }.freeze

  scope :in_window, ->(window, today: Date.current) {
    case window
    when "overdue" then where(required_on: ...today, status: ACTIVE_STATUSES)
    when "this_week" then where(required_on: today..today.end_of_week)
    when "next_two_weeks" then where(required_on: (today.end_of_week + 1)..(today.end_of_week + 14))
    when "later" then where(required_on: (today.end_of_week + 15)..)
    else all
    end
  }

  # Order counts per date window, in one query. Overdue only counts orders still to make.
  def self.window_counts(today: Date.current)
    eow = today.end_of_week
    binds = { today:, eow:, next_start: eow + 1, next_end: eow + 14, later: eow + 15, active: ACTIVE_STATUSES }
    conditions = [
      "sales_orders.required_on < :today AND sales_orders.status IN (:active)",
      "sales_orders.required_on BETWEEN :today AND :eow",
      "sales_orders.required_on BETWEEN :next_start AND :next_end",
      "sales_orders.required_on >= :later"
    ]
    sums = conditions.map do |condition|
      Arel.sql(sanitize_sql_array([ "COALESCE(SUM(CASE WHEN #{condition} THEN 1 ELSE 0 END), 0)", binds ]))
    end

    WINDOWS.keys.zip(unscope(:includes, :order).pick(*sums)).to_h
  end

  def total_g
    lines.sum(&:quantity_g)
  end

  def editable?
    EDITABLE_STATUSES.include?(status)
  end

  def late?(today: Date.current)
    required_on.present? && required_on < today && ACTIVE_STATUSES.include?(status)
  end

  # Cancelling takes the order's jobs off the planner too.
  def cancel!
    raise ArgumentError, "only open or scheduled orders can be cancelled" unless editable?

    transaction do
      Schedule::Editor.unschedule(self)
      reload.cancelled!
    end
  end

  # Moves between open and scheduled as the planner covers (or stops covering)
  # every line. Later statuses are left alone.
  def refresh_schedule_status!
    return unless editable?

    order_lines = lines.reload
    planned = ScheduleBlock.jobs.where(sales_order_line_id: order_lines.map(&:id)).group(:sales_order_line_id).sum(:planned_g)
    fully_planned = order_lines.any? && order_lines.all? { planned.fetch(_1.id, 0) >= _1.quantity_g }
    update!(status: fully_planned ? "scheduled" : "open") if scheduled? != fully_planned
  end

  def reopen!
    raise ArgumentError, "only cancelled orders can be reopened" unless cancelled?
    open!
  end

  def to_s = number

  private
    def customer_is_active
      errors.add(:customer, "is inactive") if customer && !customer.active?
    end

    def customer_fixed_once_lines_exist
      errors.add(:customer, "can't change once the order has lines") if customer_id_changed? && lines.exists?
    end
end
