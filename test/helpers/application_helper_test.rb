require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "kg formats grams" do
    assert_equal "1,250.5 kg", kg(1_250_500)
    assert_equal "10,040 kg", kg(10_040_000)
    assert_equal "—", kg(nil)
  end

  test "tonnes formats grams" do
    assert_equal "12.50 t", tonnes(12_500_000)
    assert_equal "1,000.00 t", tonnes(1_000_000_000)
  end

  test "money formats minor units with the currency symbol" do
    assert_equal "£1,234.56", money(123_456, "GBP")
    assert_equal "€0.05", money(5, "EUR")
    assert_equal "—", money(nil, "GBP")
  end
end
