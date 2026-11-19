# A delivery to a customer: pallets from the production logs of one sales order.
#
# draft → dispatched (by mark_dispatched!), and back to draft until it has
# been exported to Sage. Dispatching sets the order "dispatched" once every
# order line has gone out in full (SalesOrder#refresh_dispatch_status!).
class DeliveryNote < ApplicationRecord
  include SequentialNumber
  numbered_with "DN" # Working assumption, see PLAN.md §11 Q65.

  belongs_to :sales_order
  belongs_to :dispatched_by, class_name: "User", optional: true
  belongs_to :sage_export, optional: true
  has_many :note_pallets, -> { order(:production_run_id, :pallet_no) }, class_name: "DeliveryNotePallet",
           inverse_of: :delivery_note, dependent: :destroy

  enum :status, { draft: "draft", dispatched: "dispatched" }, default: :draft, validate: true

  normalizes :haulier, :vehicle_reg, with: ->(text) { text.squish.presence }
  normalizes :delivery_address, :notes, with: ->(text) { text.strip.presence }

  validates :dispatched_on, presence: true, if: :dispatched?

  delegate :customer, to: :sales_order

  scope :recent_first, -> { order(created_at: :desc, number: :desc) }
  scope :not_exported, -> { dispatched.where(exported_at: nil) }

  # One line per order line (spec) on the note.
  Line = Data.define(:order_line, :pallets) do
    def weight_g = pallets.sum(&:weight_g)
    def reel_count = pallets.sum(&:reel_count)

    # The line's value at the order's price per tonne, rounded half up to the
    # penny with integer maths (like PurchaseOrderLine#total_cents). Nil without a price.
    def net_cents
      price = order_line.price_per_tonne_cents
      price && (weight_g * price + Weight::GRAMS_PER_TONNE / 2) / Weight::GRAMS_PER_TONNE
    end
  end

  def editable? = draft?
  def exported? = exported_at.present?

  def pallets
    note_pallets.includes(production_run: [ :reels, :product_spec, :sales_order_line ]).map(&:pallet)
  end

  def lines
    pallets.group_by(&:order_line).map { |order_line, pallets| Line.new(order_line:, pallets:) }
  end

  def total_g = pallets.sum(&:weight_g)

  # Replaces the pallets on a draft note: [[run_id, pallet_no], …].
  def set_pallets!(keys)
    raise ArgumentError, "#{number} has been dispatched, so its pallets can't change" unless draft?

    transaction do
      note_pallets.destroy_all
      keys.uniq.each { |run_id, pallet_no| note_pallets.create!(production_run_id: run_id, pallet_no:) }
    end
    note_pallets.reset
  end

  def mark_dispatched!(user: nil, on: Date.current)
    raise ArgumentError, "#{number} has already been dispatched" unless draft?
    raise ArgumentError, "Add at least one pallet first" if note_pallets.none?
    raise ArgumentError, "The dispatch date can't be in the future" if on > Date.current

    transaction do
      update!(status: "dispatched", dispatched_on: on, dispatched_by: user)
      sales_order.reload.refresh_dispatch_status!
    end
  end

  # A mistake: back to draft, until it's been sent to Sage.
  def undo_dispatch!
    raise ArgumentError, "#{number} has been exported to Sage, so it can't change" if exported?
    raise ArgumentError, "#{number} hasn't been dispatched" unless dispatched?

    transaction do
      update!(status: "draft", dispatched_on: nil, dispatched_by: nil)
      sales_order.reload.refresh_dispatch_status!
    end
  end

  # Why it can't go to Sage yet (empty when it can).
  def export_problems
    problems = []
    problems << "#{customer.name} has no Sage account reference" if customer.sage_account_ref.blank?
    lines.each do |line|
      problems << "#{line.order_line.product_spec} has no price per tonne on #{sales_order.number}" if line.order_line.price_per_tonne_cents.nil?
    end
    problems
  end

  def to_s = number
end
