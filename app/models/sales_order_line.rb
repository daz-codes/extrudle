class SalesOrderLine < ApplicationRecord
  QUANTITY_UNITS = %w[ kg t ].freeze

  belongs_to :sales_order, inverse_of: :lines
  belongs_to :product_spec

  attribute :quantity_unit, :string, default: "kg"

  validates :quantity_g, numericality: { only_integer: true, greater_than: 0 }
  validates :quantity_unit, inclusion: { in: QUANTITY_UNITS }
  validates :price_per_tonne_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :quantity_input_is_a_number
  validate :price_input_is_a_number
  validate :spec_suits_the_order, if: -> { new_record? || will_save_change_to_product_spec_id? }
  validate :order_is_editable

  normalizes :customer_batch_no, with: ->(no) { no.strip.presence }

  delegate :customer, to: :sales_order

  # The quantity as typed, in the chosen unit ("12.5" with quantity_unit "t").
  def quantity
    return @quantity_input if @quantity_input_invalid
    return nil if quantity_g.nil?

    divisor = quantity_unit == "t" ? Weight::GRAMS_PER_TONNE : Weight::GRAMS_PER_KG
    (BigDecimal(quantity_g) / divisor).to_s("F").delete_suffix(".0")
  end

  # Order matters: the form sends quantity_unit before quantity, but don't rely on it.
  def quantity=(input)
    @quantity_input = input
    convert_quantity
  end

  def quantity_unit=(unit)
    super
    convert_quantity if defined?(@quantity_input)
  end

  def price_per_tonne
    return @price_input if @price_input_invalid
    return nil if price_per_tonne_cents.nil?

    major, minor = price_per_tonne_cents.divmod(100)
    "#{major}.#{minor.to_s.rjust(2, "0")}"
  end

  def price_per_tonne=(input)
    @price_input = input
    @price_input_invalid = false
    self.price_per_tonne_cents = Money.parse(input)
  rescue Money::InvalidInput
    @price_input_invalid = true
  end

  def currency
    customer.currency
  end

  private
    def convert_quantity
      @quantity_input_invalid = false
      self.quantity_g = Weight.parse(@quantity_input, unit: QUANTITY_UNITS.include?(quantity_unit) ? quantity_unit : "kg")
    rescue Weight::InvalidInput
      @quantity_input_invalid = true
    end

    def quantity_input_is_a_number
      errors.add(:quantity, :not_a_number) if @quantity_input_invalid
    end

    def price_input_is_a_number
      errors.add(:price_per_tonne, :not_a_number) if @price_input_invalid
    end

    def spec_suits_the_order
      return unless product_spec && sales_order

      errors.add(:product_spec, "is inactive") unless product_spec.active?
      if product_spec.customer_id && product_spec.customer_id != sales_order.customer_id
        errors.add(:product_spec, "belongs to another customer")
      end
    end

    def order_is_editable
      errors.add(:base, "Order #{sales_order.number} is #{sales_order.status.humanize.downcase} and can't be changed") if sales_order && !sales_order.editable?
    end
end
