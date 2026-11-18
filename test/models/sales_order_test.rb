require "test_helper"

class SalesOrderTest < ActiveSupport::TestCase
  test "numbers new orders in sequence" do
    order = SalesOrder.create!(customer: customers(:rhine), required_on: Date.current + 7)
    assert_equal "SO-00005", order.number
    assert_equal "SO-00006", SalesOrder.next_number
  end

  test "needs an active customer and a required date" do
    order = SalesOrder.new(customer: customers(:dormant))
    assert_not order.valid?
    assert order.errors.of_kind?(:customer, :invalid) || order.errors.include?(:customer)
    assert order.errors.include?(:required_on)
  end

  test "customer can't change once there are lines" do
    order = sales_orders(:bf_open)
    order.customer = customers(:rhine)
    assert_not order.valid?
    assert order.errors.include?(:customer)
  end

  test "customer PO ref is tidied" do
    order = SalesOrder.new(customer_po_ref: " m15159 ")
    assert_equal "M15159", order.customer_po_ref
    assert_nil SalesOrder.new(customer_po_ref: " ").customer_po_ref
  end

  test "total is the sum of line grams" do
    assert_equal 10_000_000, sales_orders(:bf_open).total_g
  end

  test "late only when active and past the required date" do
    assert sales_orders(:bf_overdue).late?
    assert_not sales_orders(:bf_open).late?
    assert_not sales_orders(:bf_dispatched).late?
  end

  test "date windows" do
    today = Date.current
    assert_includes SalesOrder.in_window("overdue", today:), sales_orders(:bf_overdue)
    assert_not_includes SalesOrder.in_window("overdue", today:), sales_orders(:bf_open)
    assert_includes SalesOrder.in_window("later", today:), sales_orders(:rhine_later)
    assert_equal SalesOrder.count, SalesOrder.in_window(nil).count
  end

  test "sorted by required date with urgent first on the same day" do
    urgent = SalesOrder.create!(customer: customers(:rhine), required_on: sales_orders(:bf_open).required_on, urgent: true)
    same_day = SalesOrder.active.by_required_date.select { _1.required_on == urgent.required_on }
    assert_equal urgent, same_day.first
  end

  test "active scope excludes finished and cancelled orders" do
    assert_not_includes SalesOrder.active, sales_orders(:bf_dispatched)
  end

  test "cancel and reopen" do
    order = sales_orders(:bf_open)
    order.cancel!
    assert order.cancelled?
    assert_not order.editable?
    order.reopen!
    assert order.open?

    assert_raises(ArgumentError) { sales_orders(:bf_dispatched).cancel! }
    assert_raises(ArgumentError) { sales_orders(:bf_open).reopen! }
  end

  test "search" do
    assert_includes SalesOrder.search("p157"), sales_orders(:bf_overdue)
    assert_includes SalesOrder.search("rhine"), sales_orders(:rhine_later)
  end
end
