# Lets forms work in human units while the database stores integers
# (see CLAUDE.md: no decimals or floats in the database).
#
#   scaled_attribute :max_reel_kg,  column: :max_reel_g,  scale: 1_000  # kg  <-> grams
#   scaled_attribute :silicone_pct, column: :silicone_bp, scale: 100    # %   <-> basis points
#
# Input is parsed with BigDecimal. Invalid input keeps the raw text for the form
# and adds a validation error instead of raising.
module ScaledAttributes
  extend ActiveSupport::Concern

  included do
    validate :validate_scaled_attribute_input
  end

  class_methods do
    def scaled_attribute(name, column:, scale:)
      define_method(name) do
        raw = scaled_attribute_raw_input[name]
        return raw if raw

        value = self[column]
        value && (BigDecimal(value) / scale).to_s("F").delete_suffix(".0")
      end

      define_method("#{name}=") do |input|
        scaled_attribute_raw_input.delete(name)
        text = input.to_s.delete(", _").strip

        if text.empty?
          self[column] = nil
        else
          self[column] = (BigDecimal(text) * scale).round(0, :half_up).to_i
        end
      rescue ArgumentError
        scaled_attribute_raw_input[name] = input.to_s
      end
    end
  end

  private
    def scaled_attribute_raw_input
      @scaled_attribute_raw_input ||= {}
    end

    def validate_scaled_attribute_input
      scaled_attribute_raw_input.each_key { |name| errors.add(name, :not_a_number) }
    end
end
