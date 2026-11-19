# A weight typed in kg or tonnes, stored as integer grams in `quantity_g`
# with the unit kept in `quantity_unit`, so a line entered in tonnes reopens in tonnes.
#
#   line.quantity_unit = "t"
#   line.quantity = "12.5"   # quantity_g => 12_500_000
#
# Input finer than a gram is rejected, not rounded. Invalid text is kept for the
# form and reported as a validation error on `quantity`.
module EnteredQuantity
  extend ActiveSupport::Concern

  UNITS = { "kg" => Weight::GRAMS_PER_KG, "t" => Weight::GRAMS_PER_TONNE }.freeze
  UNIT_LABELS = { "kg" => "kg", "t" => "tonnes" }.freeze

  included do
    validates :quantity_g, numericality: { only_integer: true, greater_than: 0 }, unless: :quantity_input_invalid?
    validates :quantity_unit, inclusion: { in: UNITS.keys }
    validate :quantity_input_is_valid
    after_validation :report_quantity_errors_on_the_form_field
  end

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
      UNITS.fetch(quantity_unit, Weight::GRAMS_PER_KG)
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
end
