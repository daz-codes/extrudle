require "test_helper"

class MasterDataTest < ActiveSupport::TestCase
  test "customer names are unique regardless of case" do
    customer = Customer.new(name: "brightform packaging ltd")
    assert_not customer.valid?
    assert customer.errors.of_kind?(:name, :taken)
  end

  test "customer currency must be supported" do
    assert_not Customer.new(name: "Yen Co", currency: "JPY").valid?
  end

  test "active scope and including_inactive" do
    assert_not_includes Customer.active, customers(:dormant)
    assert_includes Customer.including_inactive(true), customers(:dormant)
    assert_not_includes Customer.including_inactive(false), customers(:dormant)
  end

  test "customers with specs can't be destroyed" do
    assert_not customers(:brightform).destroy
  end

  test "supplier incoterm is normalised and validated" do
    supplier = Supplier.new(name: "New Resin", incoterm: " fob ")
    assert_equal "FOB", supplier.incoterm
    assert supplier.valid?

    supplier.incoterm = "ABC"
    assert_not supplier.valid?

    supplier.incoterm = " "
    assert_nil supplier.incoterm
    assert supplier.valid?
  end

  test "in-house materials have no supplier" do
    material = materials(:regrind)
    assert material.valid?

    material.supplier = suppliers(:albion)
    assert_not material.valid?
    assert material.errors.include?(:supplier)
  end

  test "materials need a category" do
    assert_not Material.new(name: "Mystery").valid?
  end

  test "line names are upper-cased and changeover can't be negative" do
    line = Line.new(name: " d3 ", default_changeover_minutes: -30)
    assert_equal "D3", line.name
    assert_not line.valid?
    assert line.errors.include?(:default_changeover_minutes)
  end

  test "line rates are whole positive kg/h, one per line per spec" do
    assert_not LineRate.new(line: lines(:d1), product_spec: product_specs(:stock), kg_per_hour: 0).valid?
    assert_not LineRate.new(line: lines(:d1), product_spec: product_specs(:stock), kg_per_hour: 12.5).valid?
    assert_not LineRate.new(line: lines(:d1), product_spec: product_specs(:bf_700), kg_per_hour: 200).valid?
    assert LineRate.new(line: lines(:d1), product_spec: product_specs(:stock), kg_per_hour: 230).valid?
  end
end
