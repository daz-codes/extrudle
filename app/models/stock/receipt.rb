# Goods in: one delivery of one material, as a number of bags. Each bag becomes
# a Lot with a receipt StockMovement.
#
# Against a PO line (the usual case), or without one for opening stock and
# in-house regrind (pass material_id instead).
#
# The total net weight is split evenly across the bags with the largest-remainder
# method, so the lots add up exactly to what was delivered. Working assumption,
# see PLAN.md §11 Q26: correct a single bag afterwards with Stock::Adjustment.
class Stock::Receipt
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations::Callbacks

  MAX_BAGS = 100

  attribute :material_id, :integer
  attribute :received_on, :date, default: -> { Date.current }
  attribute :bags, :integer, default: 1
  attribute :first_bag_no, :string
  attribute :supplier_lot_ref, :string
  attribute :delivery_ref, :string
  attribute :location, :string, default: "on_site"
  attribute :notes, :string
  attribute :quantity_g, :integer
  attribute :quantity_unit, :string, default: "kg"

  # After the attributes, so its quantity_unit= wraps the generated one.
  include EnteredQuantity

  attr_reader :purchase_order_line, :lots
  attr_accessor :user

  validates :received_on, presence: true
  validates :bags, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: MAX_BAGS }
  validates :location, inclusion: { in: Lot::LOCATIONS.keys }
  validate :material_can_be_received
  validate :po_can_be_received, if: :purchase_order_line
  validate :every_bag_weighs_something

  def initialize(purchase_order_line: nil, **attributes)
    @purchase_order_line = purchase_order_line
    super(**attributes)
    self.material_id = purchase_order_line.material_id if purchase_order_line
  end

  def material
    @material = nil if @material&.id != material_id
    @material ||= Material.find_by(id: material_id)
  end

  def purchase_order = purchase_order_line&.purchase_order
  def purchase_order_line_id = purchase_order_line&.id

  # Bag numbers count up from the first one: "939" → "940", "A12" → "A13".
  def bag_numbers
    return Array.new(bags.to_i) if first_bag_no.blank?

    Array.new(bags.to_i).each_with_object([]) { |_, numbers| numbers << (numbers.last&.succ || first_bag_no.strip) }
  end

  def save!
    save || raise(ActiveRecord::RecordInvalid.new(self))
  end

  def save(attempts: 3)
    return false unless valid?

    ActiveRecord::Base.transaction do
      @lots = create_lots
      purchase_order&.refresh_receipt_status!
    end
    true
  rescue ActiveRecord::RecordNotUnique
    retry if (attempts -= 1).positive?
    raise
  end

  private
    def create_lots
      codes = Lot.next_codes(bags, year: received_on.year)
      weights = Allocation.evenly(quantity_g, bags)
      moved_at = received_on == Date.current ? Time.current : received_on.in_time_zone.change(hour: 12)

      codes.zip(weights, bag_numbers).map do |code, weight_g, bag_no|
        lot = Lot.create!(code:, material:, purchase_order_line:, supplier_lot_ref:, bag_no:, delivery_ref:,
                          location:, received_on:, initial_g: weight_g, notes:)
        lot.movements.create!(kind: "receipt", quantity_g: weight_g, to_location: location, user:, moved_at:)
        lot
      end
    end

    def material_can_be_received
      if material.nil?
        errors.add(:material_id, :blank)
      elsif !material.active?
        errors.add(:material_id, "is inactive")
      end
    end

    def po_can_be_received
      return if purchase_order.receivable?

      errors.add(:base, "#{purchase_order.number} is #{purchase_order.status.humanize.downcase}, so goods can't be received against it")
    end

    def every_bag_weighs_something
      return if errors.include?(:quantity) || errors.include?(:bags) || quantity_g.nil?

      errors.add(:quantity, "is too small to split into #{bags} bags") if quantity_g < bags.to_i
    end
end
