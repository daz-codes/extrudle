require "test_helper"

class MoneyTest < ActiveSupport::TestCase
  test "parses amounts into integer minor units" do
    assert_equal 123_456, Money.parse("1,234.56")
    assert_equal 1_000, Money.parse("10")
    assert_equal 1, Money.parse("0.005")
  end

  test "blank is nil and nonsense raises" do
    assert_nil Money.parse(" ")
    assert_raises(Money::InvalidInput) { Money.parse("ten pounds") }
  end

  test "rejects a decimal comma, non-finite and exponent input" do
    %w[1,5 12,50 NaN Infinity 1e3].each do |input|
      assert_raises(Money::InvalidInput, input) { Money.parse(input) }
    end
  end

  test "currency symbols" do
    assert_equal "£", Money.symbol("GBP")
    assert_equal "€", Money.symbol("eur")
    assert_raises(ArgumentError) { Money.symbol("JPY") }
  end
end
