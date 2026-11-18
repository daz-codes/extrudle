# Shared parser behind Weight.parse and Money.parse: turns user-typed decimal
# text into an integer number of the smallest unit, via BigDecimal (never Float).
#
# Commas are accepted only as UK thousands separators ("1,250.5"). Anything
# else with a comma, such as the European decimal comma in "1,5", is rejected
# rather than silently read as 15. Exponents, NaN and Infinity are rejected too.
module DecimalInput
  class Invalid < ArgumentError; end

  PLAIN   = /\A[+-]?(\d+(\.\d*)?|\.\d+)\z/
  GROUPED = /\A[+-]?\d{1,3}(,\d{3})+(\.\d*)?\z/

  module_function

  # DecimalInput.to_scaled_integer("1,250.5", 1_000) #=> 1_250_500
  def to_scaled_integer(input, multiplier)
    return input * multiplier if input.is_a?(Integer)

    text = input.to_s.strip
    raise Invalid unless text.match?(PLAIN) || text.match?(GROUPED)

    (BigDecimal(text.delete(",")) * multiplier).round(0, :half_up).to_i
  end
end
