# Lets forms work in human units while the database stores integers
# (see CLAUDE.md: no decimals or floats in the database).
#
#   scaled_attribute :max_reel_kg,  column: :max_reel_g,  scale: Weight::GRAMS_PER_KG  # kg <-> grams
#   scaled_attribute :silicone_pct, column: :silicone_bp, scale: 100                   # %  <-> basis points
#   scaled_attribute :price_per_tonne, column: :price_per_tonne_cents, scale: 100, pad: true  # "1850.00"
#
# Parsing and formatting go through DecimalInput, the same parser behind Weight.parse
# and Money.parse. Input finer than the stored unit is rejected rather than rounded.
# Invalid input keeps the raw text for the form and adds a validation error instead of raising.
# Errors on the integer column are reported on the form attribute, so they show next to the field.
module ScaledAttributes
  extend ActiveSupport::Concern

  included do
    class_attribute :scaled_attributes, instance_writer: false, default: {}
    validate :validate_scaled_attribute_input
    after_validation :move_scaled_column_errors
  end

  class_methods do
    # pad: true always shows every decimal place (money: "1850.00", not "1850").
    def scaled_attribute(name, column:, scale:, pad: false)
      self.scaled_attributes = scaled_attributes.merge(name => { column:, scale: })

      define_method(name) do
        raw = scaled_attribute_raw_input[name]
        return raw[:text] if raw

        value = self[column]
        value && DecimalInput.from_scaled_integer(value, scale, pad:)
      end

      define_method("#{name}=") do |input|
        scaled_attribute_raw_input.delete(name)
        self[column] = input.to_s.strip.empty? ? nil : DecimalInput.to_scaled_integer(input, scale, exact: true)
      rescue DecimalInput::TooPrecise
        scaled_attribute_raw_input[name] = { text: input.to_s, error: :too_precise, places: DecimalInput.places(scale) }
      rescue DecimalInput::Invalid
        scaled_attribute_raw_input[name] = { text: input.to_s, error: :not_a_number }
      end
    end
  end

  # Blank a scaled attribute, including any invalid text typed into it.
  # Use when the field doesn't apply, e.g. silicone % when there is no silicone.
  def clear_scaled_attribute(name)
    scaled_attribute_raw_input.delete(name)
    self[scaled_attributes.fetch(name)[:column]] = nil
  end

  private
    def scaled_attribute_raw_input
      @scaled_attribute_raw_input ||= {}
    end

    def validate_scaled_attribute_input
      scaled_attribute_raw_input.each do |name, raw|
        if raw[:error] == :too_precise
          errors.add(name, :too_precise, message: "can have at most #{raw[:places]} decimal places")
        else
          errors.add(name, :not_a_number)
        end
      end
    end

    def move_scaled_column_errors
      scaled_attributes.each do |name, options|
        column = options[:column]
        next unless errors.include?(column)

        errors.where(column).each { |error| errors.import(error, attribute: name) }
        errors.delete(column)
      end
    end
end
