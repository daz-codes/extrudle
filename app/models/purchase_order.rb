class PurchaseOrder < ApplicationRecord
  include SequentialNumber
  numbered_with "PO" # Working assumption, see PLAN.md §11 Q18.

  belongs_to :supplier
  has_many :lines, -> { order(:id) }, class_name: "PurchaseOrderLine", inverse_of: :purchase_order, dependent: :destroy

  # part_received and received are set by goods in (Stock::Receipt).
  enum :status, {
    draft: "draft", sent: "sent", part_received: "part_received", received: "received", cancelled: "cancelled"
  }, default: :draft, validate: true

  # Still waiting for (some of) the goods.
  OUTSTANDING_STATUSES = %w[ sent part_received ].freeze
  # Only drafts can be changed. A sent PO goes back to draft to be amended and
  # sent again. Working assumption, see PLAN.md §11 Q22.
  EDITABLE_STATUSES = %w[ draft ].freeze

  normalizes :supplier_ref, with: ->(ref) { ref.strip.presence }
  normalizes :incoterm, with: ->(term) { term.strip.upcase.presence }

  validates :expected_on, presence: true
  validates :currency, inclusion: { in: Currency::CODES }
  validates :incoterm, inclusion: { in: Currency::INCOTERMS }, allow_nil: true
  validate :supplier_is_active, if: -> { new_record? || will_save_change_to_supplier_id? }
  validate :supplier_and_currency_fixed_once_lines_exist, on: :update

  before_validation :take_terms_from_supplier, if: -> { new_record? || supplier_id_changed? }

  scope :outstanding, -> { where(status: OUTSTANDING_STATUSES) }
  scope :active, -> { where(status: %w[ draft ] + OUTSTANDING_STATUSES) }
  scope :by_expected_date, -> { order(expected_on: :asc, number: :asc) }
  scope :search, ->(q) {
    next all if q.blank?
    like = "%#{sanitize_sql_like(q)}%"
    left_joins(:supplier).where("purchase_orders.number LIKE :q OR purchase_orders.supplier_ref LIKE :q OR suppliers.name LIKE :q", q: like)
  }

  # Exact, in minor units: the sum of the rounded line totals, as printed on the PO.
  def total_cents
    lines.sum(&:total_cents)
  end

  def total_g
    lines.sum(&:quantity_g)
  end

  def editable?
    EDITABLE_STATUSES.include?(status)
  end

  def overdue?(today: Date.current)
    expected_on.present? && expected_on < today && OUTSTANDING_STATUSES.include?(status)
  end

  # The date printed on the PO: when it was sent, or today for a draft (even
  # one taken back to draft, which keeps its old sent_at until it's sent again).
  def order_date
    draft? || sent_at.nil? ? Date.current : sent_at.to_date
  end

  def mark_sent!
    raise ArgumentError, "only draft purchase orders can be sent" unless draft?
    raise ArgumentError, "add at least one line before sending" if lines.none?
    raise ArgumentError, "#{supplier.name} is inactive" unless supplier.active?

    update!(status: "sent", sent_at: Time.current)
  end

  # Takes a sent PO back to draft so it can be amended and sent again.
  def back_to_draft!
    raise ArgumentError, "only sent purchase orders can go back to draft" unless sent?

    update!(status: "draft")
  end

  def cancel!
    raise ArgumentError, "only draft or sent purchase orders can be cancelled" unless draft? || sent?

    cancelled!
  end

  def reopen!
    raise ArgumentError, "only cancelled purchase orders can be reopened" unless cancelled?

    update!(status: "draft", sent_at: nil)
  end

def receivable? = OUTSTANDING_STATUSES.include?(status)

def received_g
  lines.sum(&:received_g)
end

# After goods in: part_received until every line has had at least what was
# ordered, then received. Over-deliveries are allowed. Working assumption,
# see PLAN.md §11 Q27.
def refresh_receipt_status!
  return unless receivable?

  order_lines = lines.includes(:lots).reload
  status = if order_lines.all?(&:fully_received?) then "received"
  elsif order_lines.any? { _1.received_g.positive? } then "part_received"
  else "sent"
  end
  update!(status:) if status != self.status
end

# Accepts a short delivery: nothing more is expected against this PO.
def close_short!
  raise ArgumentError, "only part-received purchase orders can be closed short" unless part_received?

  update!(status: "received", closed_short_at: Time.current)
end

def closed_short? = closed_short_at.present?

def to_s = number

  private
    # On create, and when a PO without lines moves to another supplier. A currency
    # or incoterm chosen in the same edit wins over the supplier's.
    def take_terms_from_supplier
      return unless supplier

      self.currency = supplier.currency unless currency_changed?
      self.incoterm = supplier.incoterm unless incoterm_changed?
    end

    def supplier_is_active
      errors.add(:supplier, "is inactive") if supplier && !supplier.active?
    end

    def supplier_and_currency_fixed_once_lines_exist
      return unless lines.exists?

      errors.add(:supplier, "can't change once the PO has lines") if supplier_id_changed?
      errors.add(:currency, "can't change once the PO has lines, because the prices are in it") if currency_changed?
    end
end
