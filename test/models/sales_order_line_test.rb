require "test_helper"

class SalesOrderLineTest < ActiveSupport::TestCase
  def line(**attrs)
    SalesOrderLine.new({ sales_order: sales_orders(:bf_open), product_spec: product_specs(:bf_700) }.merge(attrs))
  end

  test "quantity in kg is stored as grams" do
    l = line(quantity: "10,040.5")
    assert l.valid?, l.errors.full_messages.to_sentence
    assert_equal 10_040_500, l.quantity_g
    assert_equal "10040.5", l.quantity
  end

  test "quantity in tonnes, whichever order the attributes arrive in" do
    assert_equal 12_500_000, line(quantity_unit: "t", quantity: "12.5").quantity_g
    assert_equal 12_500_000, line(quantity: "12.5", quantity_unit: "t").quantity_g
  end

  test "quantity must be a positive number" do
    assert_not line(quantity: "").valid?
    assert_not line(quantity: "0").valid?

    bad = line(quantity: "lots")
    assert_not bad.valid?
    assert bad.errors.of_kind?(:quantity, :not_a_number)
    assert_equal "lots", bad.quantity
  end

  test "price per tonne is optional and stored in minor units" do
    l = line(quantity: "1000", price_per_tonne: "1,850")
    assert_equal 185_000, l.price_per_tonne_cents
    assert_equal "1850.00", l.price_per_tonne
    assert_equal "GBP", l.currency
    assert_nil line(quantity: "1", price_per_tonne: "").price_per_tonne_cents
    assert_not line(quantity: "1", price_per_tonne: "cheap").valid?
  end

  test "price keeps the currency it was agreed in" do
    l = line(quantity: "1000", price_per_tonne: "1200")
    l.save!
    assert_equal "GBP", l.currency

    customers(:brightform).update!(currency: "EUR")
    assert_equal "GBP", l.reload.currency
    assert_equal "EUR", line(sales_order: sales_orders(:bf_open).reload, quantity: "1").tap(&:validate).currency
  end

  test "the unit is kept, so a line entered in tonnes reopens in tonnes" do
    l = line(quantity_unit: "t", quantity: "12.5")
    l.save!
    l = SalesOrderLine.find(l.id)
    assert_equal "t", l.quantity_unit
    assert_equal "12.5", l.quantity
  end

  test "quantities finer than a gram are rejected, not rounded" do
    assert_not line(quantity: "1.0005").valid?
    bad = line(quantity_unit: "t", quantity: "1.0000001")
    assert_not bad.valid?
    assert_includes bad.errors.full_messages, "Quantity can't be finer than 1 g (6 decimal places in t)"
    assert line(quantity_unit: "t", quantity: "1.000001").valid?
  end

  test "a bad quantity gives one error, on the quantity field" do
    bad = line(quantity: "lots")
    bad.validate
    assert_equal [ "Quantity is not a number" ], bad.errors.full_messages

    zero = line(quantity: "0")
    zero.validate
    assert_equal [ "Quantity must be greater than 0" ], zero.errors.full_messages
  end

  test "prices with more than 2 decimal places are rejected" do
    l = line(quantity: "1", price_per_tonne: "12.345")
    assert_not l.valid?
    assert_includes l.errors.full_messages, "Price per tonne can have at most 2 decimal places"
  end

  test "spec must be the customer's own or a stock spec" do
    assert line(quantity: "1", product_spec: product_specs(:stock)).valid?

    other = line(quantity: "1", sales_order: sales_orders(:rhine_later))
    assert_not other.valid?
    assert other.errors.include?(:product_spec)
  end

  test "inactive specs can't be added" do
    product_specs(:stock).update!(active: false)
    assert_not line(quantity: "1", product_spec: product_specs(:stock)).valid?
  end

  test "lines on dispatched orders can't change" do
    l = sales_order_lines(:bf_dispatched_700)
    l.quantity = "1"
    assert_not l.valid?
    assert l.errors.include?(:base)
  end
end
