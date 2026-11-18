# Money is stored as integer minor units (pence/cents) plus a currency code.
# No exchange-rate maths in the MVP.
module Money
  CURRENCIES = { "GBP" => "£", "EUR" => "€", "USD" => "$" }.freeze

  class InvalidInput < ArgumentError; end

  module_function

  # Money.parse("1,234.56") #=> 123_456
  def parse(input)
    return nil if input.nil? || input.to_s.strip.empty?

    DecimalInput.to_scaled_integer(input, 100)
  rescue DecimalInput::Invalid
    raise InvalidInput, "#{input.inspect} is not a valid amount"
  end

  def symbol(currency)
    CURRENCIES.fetch(currency.to_s.upcase) { raise ArgumentError, "unsupported currency #{currency.inspect}" }
  end

  def to_major(cents)
    BigDecimal(cents) / 100
  end
end
