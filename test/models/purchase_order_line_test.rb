require "test_helper"

class PurchaseOrderLineTest < ActiveSupport::TestCase
  def line(**attrs)
    PurchaseOrderLine.new({ purchase_order: purchase_orders(:pacific_draft), material: materials(:jade), price_per_tonne: "1,240" }.merge(attrs))
  end

  test "quantity in kg or tonnes is stored as grams and keeps its unit" do
    assert_equal 1_100_000, line(quantity: "1,100").quantity_g
    l = line(quantity: "22.5", quantity_unit: "t")
    assert_equal 22_500_000, l.quantity_g
    l.save!
    assert_equal "22.5", PurchaseOrderLine.find(l.id).quantity
  end

  test "quantity must be a positive number no finer than a gram" do
    assert_not line(quantity: "0").valid?
    assert line(quantity: "lots").tap(&:validate).errors.of_kind?(:quantity, :not_a_number)
    assert_not line(quantity: "1.0005").valid?
  end

  test "price per tonne is required and stored in minor units" do
    assert_equal 124_000, line(quantity: "1").price_per_tonne_cents
    assert_not line(quantity: "1", price_per_tonne: "").valid?
    assert_not line(quantity: "1", price_per_tonne: "cheap").valid?
    assert_not line(quantity: "1", price_per_tonne: "1.234").valid?
  end

  test "total is quantity times price per tonne, rounded half up to the penny" do
    assert_equal 2_728_000, line(quantity: "22", quantity_unit: "t").total_cents # 22 t × 1,240.00
    assert_equal 1, line(quantity: "0.005", price_per_tonne: "1000").total_cents  # 0.5 p
    assert_equal 0, line(quantity: "0.004", price_per_tonne: "1000").total_cents  # 0.4 p
    assert_equal 1_364_00, line(quantity: "1100").total_cents
  end

  test "in-house and inactive materials can't be bought" do
    assert line(quantity: "1", material: materials(:regrind)).tap(&:validate).errors.include?(:material)
    materials(:jade).update!(active: false)
    assert_not line(quantity: "1").valid?
  end

  test "lines can only change on a draft" do
    l = purchase_order_lines(:albion_jade)
    l.quantity = "2000"
    assert_not l.valid?
    assert_match "Take it back to draft", l.errors[:base].first
  end

  test "currency comes from the PO" do
    assert_equal "USD", line.currency
  end
end
