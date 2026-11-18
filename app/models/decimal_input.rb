# Shared parser behind Weight.parse and Money.parse: turns user-typed decimal
# text into an integer number of the smallest unit, via BigDecimal (never Float).
#
# Commas are accepted only as UK thousands separators ("1,250.5"). Anything
# else with a comma, such as the European decimal comma in "1,5", is rejected
# rather than silently read as 15. Exponents, NaN and Infinity are rejected too.
module DecimalInput
  class Invalid < ArgumentError; end
  # The input has more decimal places than the smallest unit can hold.
  class TooPrecise < Invalid; end

  PLAIN   = /\A[+-]?(\d+(\.\d*)?|\.\d+)\z/
  GROUPED = /\A[+-]?\d{1,3}(,\d{3})+(\.\d*)?\z/

  module_function

  # DecimalInput.to_scaled_integer("1,250.5", 1_000) #=> 1_250_500
  # Extra precision is rounded half up, unless exact: true, which raises TooPrecise.
  def to_scaled_integer(input, multiplier, exact: false)
    return input * multiplier if input.is_a?(Integer)

    text = input.to_s.strip
    raise Invalid unless text.match?(PLAIN) || text.match?(GROUPED)

    scaled = BigDecimal(text.delete(",")) * multiplier
    raise TooPrecise if exact && scaled.frac.nonzero?

    scaled.round(0, :half_up).to_i
  end

  # The inverse, as plain text a form can send back: (1_250_500, 1_000) #=> "1250.5"
  def from_scaled_integer(value, multiplier)
    (BigDecimal(value) / multiplier).to_s("F").delete_suffix(".0")
  end

  # Decimal places a multiplier allows: 1_000 => 3, 100 => 2.
  def places(multiplier)
    multiplier.to_s.count("0")
  end
end
