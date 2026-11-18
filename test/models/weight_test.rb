require "test_helper"

class WeightTest < ActiveSupport::TestCase
  test "parses kilograms into integer grams" do
    assert_equal 1_250_500, Weight.parse("1,250.5")
    assert_equal 1_000, Weight.parse("1")
    assert_equal 1, Weight.parse("0.001")
    assert_kind_of Integer, Weight.parse("12.345")
  end

  test "parses tonnes and grams" do
    assert_equal 12_500_000, Weight.parse("12.5", unit: "t")
    assert_equal 750, Weight.parse("750", unit: "g")
  end

  test "rounds sub-gram input half up" do
    assert_equal 2, Weight.parse("0.0015")
    assert_equal 1, Weight.parse("0.0014")
  end

  test "has no float error when adding many small weights" do
    total = Array.new(1_000) { Weight.parse("0.1") }.sum
    assert_equal 100_000, total
  end

  test "handles negatives for adjustments" do
    assert_equal(-2_500, Weight.parse("-2.5"))
  end

  test "blank input is nil" do
    assert_nil Weight.parse("")
    assert_nil Weight.parse(nil)
  end

  test "rejects nonsense and unknown units" do
    assert_raises(Weight::InvalidInput) { Weight.parse("lots") }
    assert_raises(Weight::InvalidInput) { Weight.parse("1", unit: "lb") }
  end

  test "rejects a decimal comma instead of reading it as thousands" do
    assert_raises(Weight::InvalidInput) { Weight.parse("1,5") }
    assert_raises(Weight::InvalidInput) { Weight.parse("12,50") }
    assert_raises(Weight::InvalidInput) { Weight.parse("1,2345.6") }
    assert_equal 1_250_000_000, Weight.parse("1,250,000")
  end

  test "rejects non-finite and exponent input" do
    %w[NaN Infinity -Infinity 1e3 0x10].each do |input|
      assert_raises(Weight::InvalidInput, input) { Weight.parse(input) }
    end
  end

  test "integer input with an unknown unit raises InvalidInput" do
    assert_equal 5_000, Weight.parse(5)
    assert_raises(Weight::InvalidInput) { Weight.parse(5, unit: "lb") }
  end

  test "converts grams back to exact decimals" do
    assert_equal BigDecimal("1250.5"), Weight.to_kg(1_250_500)
    assert_equal BigDecimal("1.2505"), Weight.to_tonnes(1_250_500)
  end
end
