# Weights are stored as integer grams (see CLAUDE.md: SQLite has no true decimal type).
# This module converts user input to grams and grams to display strings.
# It never uses Float.
module Weight
  GRAMS_PER_KG = 1_000
  GRAMS_PER_TONNE = 1_000_000

  UNITS = { "g" => 1, "kg" => GRAMS_PER_KG, "t" => GRAMS_PER_TONNE }.freeze

  class InvalidInput < ArgumentError; end

  module_function

  # Weight.parse("1,250.5")            #=> 1_250_500 (grams)
  # Weight.parse("12.5", unit: "t")    #=> 12_500_000
  # Blank input returns nil.
  def parse(input, unit: "kg")
    return nil if input.nil? || input.to_s.strip.empty?

    multiplier = UNITS.fetch(unit.to_s) { raise InvalidInput, "unknown unit #{unit.inspect}" }
    DecimalInput.to_scaled_integer(input, multiplier)
  rescue DecimalInput::Invalid
    raise InvalidInput, "#{input.inspect} is not a valid weight"
  end

  def to_kg(grams)
    BigDecimal(grams) / GRAMS_PER_KG
  end

  def to_tonnes(grams)
    BigDecimal(grams) / GRAMS_PER_TONNE
  end
end
