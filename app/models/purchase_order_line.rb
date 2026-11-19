class PurchaseOrderLine < ApplicationRecord
  include ScaledAttributes
  include EnteredQuantity

  belongs_to :purchase_order, inverse_of: :lines
  belongs_to :material
  has_many :lots, dependent: :restrict_with_error

  # In the PO's currency, per tonne. Working assumption, see PLAN.md §11 Q20.
  scaled_attribute :price_per_tonne, column: :price_per_tonne_cents, scale: 100, pad: true

  validates :price_per_tonne_cents, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :material_can_be_bought, if: -> { new_record? || will_save_change_to_material_id? }
  validate :order_is_editable

  delegate :currency, :supplier, to: :purchase_order

  # quantity × price per tonne, rounded half up to the nearest penny/cent.
  # Integer maths only (grams × cents/tonne ÷ 1,000,000). Each line is rounded
  # on its own and the PO total is the sum of the lines, as on the printed PO.
  def total_cents
    return nil if quantity_g.nil? || price_per_tonne_cents.nil?

    (quantity_g * price_per_tonne_cents + Weight::GRAMS_PER_TONNE / 2) / Weight::GRAMS_PER_TONNE
  end

  # Weight delivered against this line: what each lot weighed when it arrived.
  def received_g
    lots.loaded? ? lots.sum(&:initial_g) : lots.sum(:initial_g)
  end

  def outstanding_g
    [ quantity_g.to_i - received_g, 0 ].max
  end

  def fully_received?
    received_g >= quantity_g.to_i
  end

  private
    def material_can_be_bought
      return unless material

      errors.add(:material, "is made in-house, so it can't be bought") if material.internal?
      errors.add(:material, "is inactive") unless material.active?
    end

    def order_is_editable
      return if purchase_order.nil? || purchase_order.editable?

      errors.add(:base, "#{purchase_order.number} is #{purchase_order.status.humanize.downcase}. Take it back to draft to change it.")
    end
end
