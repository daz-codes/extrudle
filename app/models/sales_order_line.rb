class SalesOrderLine < ApplicationRecord
  include ScaledAttributes

  QUANTITY_UNITS = { "kg" => Weight::GRAMS_PER_KG, "t" => Weight::GRAMS_PER_TONNE }.freeze

  belongs_to :sales_order, inverse_of: :lines
  belongs_to :product_spec

  # The price is agreed in the customer's currency when the line is added, and kept with it.
  scaled_attribute :price_per_tonne, column: :price_per_tonne_cents, scale: 100, pad: true

  validates :quantity_g, numericality: { only_integer: true, greater_than: 0 }, unless: :quantity_input_invalid?
  validates :quantity_unit, inclusion: { in: QUANTITY_UNITS.keys }
  validates :currency, inclusion: { in: Money::CURRENCIES.keys }
  validates :price_per_tonne_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :quantity_input_is_valid
  validate :spec_suits_the_order, if: -> { new_record? || will_save_change_to_product_spec_id? }
  validate :order_is_editable

  before_validation :take_currency_from_customer, on: :create
  after_validation :report_quantity_errors_on_the_form_field

  normalizes :customer_batch_no, with: ->(no) { no.strip.presence }

  delegate :customer, to: :sales_order

  # The quantity as typed, in its unit ("12.5" with quantity_unit "t").
  def quantity
    return @quantity_input[:text] if quantity_input_invalid?
    return nil if quantity_g.nil?

    DecimalInput.from_scaled_integer(quantity_g, unit_scale)
  end

  # The form may send quantity before quantity_unit, so the text is kept and
  # parsed again if the unit changes.
  def quantity=(input)
    @quantity_text = input.to_s
    convert_quantity
  end

  def quantity_unit=(unit)
    super
    convert_quantity if defined?(@quantity_text)
  end

  private
    def unit_scale
      QUANTITY_UNITS.fetch(quantity_unit, Weight::GRAMS_PER_KG)
    end

    def convert_quantity
      @quantity_input = nil
      self.quantity_g = @quantity_text.strip.empty? ? nil : DecimalInput.to_scaled_integer(@quantity_text, unit_scale, exact: true)
    rescue DecimalInput::TooPrecise
      @quantity_input = { text: @quantity_text, error: :too_precise }
    rescue DecimalInput::Invalid
      @quantity_input = { text: @quantity_text, error: :not_a_number }
    end

    def quantity_input_invalid?
      @quantity_input.present?
    end

    def quantity_input_is_valid
      case @quantity_input&.dig(:error)
      when :too_precise
        errors.add(:quantity, :too_precise, message: "can't be finer than 1 g (#{DecimalInput.places(unit_scale)} decimal places in #{quantity_unit})")
      when :not_a_number
        errors.add(:quantity, :not_a_number)
      end
    end

    def report_quantity_errors_on_the_form_field
      return unless errors.include?(:quantity_g)

      errors.where(:quantity_g).each { |error| errors.import(error, attribute: :quantity) }
      errors.delete(:quantity_g)
    end

    def take_currency_from_customer
      self.currency = customer.currency if sales_order&.customer
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
