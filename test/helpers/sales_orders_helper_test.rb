require "test_helper"

class SalesOrdersHelperTest < ActionView::TestCase
  test "quantities are exact, never rounded" do
    assert_equal "12.345 t", order_quantity(12_345_000)
    assert_equal "1,250.5 t", order_quantity(1_250_500_000)
    assert_equal "750 kg", order_quantity(750_000)
    assert_equal "12,345 kg", order_quantity(12_345_000, unit: "kg")
    assert_equal "0.5 t", order_quantity(500_000, unit: "t")
  end
end
