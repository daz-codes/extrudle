require "test_helper"

class SalesOrderTest < ActiveSupport::TestCase
  test "numbers new orders in sequence" do
    order = SalesOrder.create!(customer: customers(:rhine), required_on: Date.current + 7)
    assert_equal "SO-00005", order.number
    assert_equal "SO-00006", SalesOrder.next_number
  end

  test "numbers keep counting past SO-99999" do
    SalesOrder.create!(customer: customers(:rhine), required_on: Date.current, number: "SO-99999")
    assert_equal "SO-100000", SalesOrder.next_number
    SalesOrder.create!(customer: customers(:rhine), required_on: Date.current)
    assert_equal "SO-100001", SalesOrder.next_number
  end

  test "a number taken at the same moment by someone else is retried, not a crash" do
    order = SalesOrder.new(customer: customers(:rhine), required_on: Date.current)
    # Another user's insert lands between our validation and our insert: the unique index rejects ours once.
    def order._create_record(*)
      @attempts = @attempts.to_i + 1
      raise ActiveRecord::RecordNotUnique, "number taken" if @attempts == 1
      super
    end

    assert order.save_with_number
    assert order.persisted?
    assert_equal 2, order.instance_variable_get(:@attempts)
  end

  test "gives up after a few clashes instead of looping" do
    order = SalesOrder.new(customer: customers(:rhine), required_on: Date.current)
    def order._create_record(*) = raise(ActiveRecord::RecordNotUnique, "number taken")
    assert_raises(ActiveRecord::RecordNotUnique) { order.save_with_number }
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

  test "a week order is stored as its Monday and is due by the Friday (Q90)" do
    order = SalesOrder.create!(customer: customers(:rhine), required_on: Date.new(2026, 12, 2), required_week: true) # a Wednesday
    assert_equal Date.new(2026, 11, 30), order.required_on
    assert_equal Date.new(2026, 12, 4), order.due_on
    assert_equal Time.zone.parse("2026-12-05 00:00"), order.deadline

    friday, saturday = Date.new(2026, 12, 4), Date.new(2026, 12, 5)
    assert_not order.late?(today: friday)
    assert order.late?(today: saturday)
    assert_not_includes SalesOrder.in_window("overdue", today: friday), order
    assert_includes SalesOrder.in_window("overdue", today: saturday), order
    [ friday, saturday ].each do |today|
      assert_equal SalesOrder.in_window("overdue", today:).count, SalesOrder.window_counts(today:)["overdue"]
    end
  end

  test "a day order's deadline is the end of its day, and the delivery site is tidied" do
    order = SalesOrder.create!(customer: customers(:rhine), required_on: Date.new(2026, 12, 2), delivery_site: "  Cinderford ")
    assert_equal [ Date.new(2026, 12, 2), Time.zone.parse("2026-12-03 00:00"), "Cinderford" ], [ order.due_on, order.deadline, order.delivery_site ]
    order.update!(delivery_site: " ")
    assert_nil order.delivery_site
  end

  test "date windows" do
    today = Date.current
    assert_includes SalesOrder.in_window("overdue", today:), sales_orders(:bf_overdue)
    assert_not_includes SalesOrder.in_window("overdue", today:), sales_orders(:bf_open)
    assert_includes SalesOrder.in_window("later", today:), sales_orders(:rhine_later)
    assert_equal SalesOrder.count, SalesOrder.in_window(nil).count
  end

  test "overdue only covers orders still to make" do
    assert_not_includes SalesOrder.in_window("overdue"), sales_orders(:bf_dispatched)
  end

  test "window counts in one query match the windows, even with includes" do
    scope = SalesOrder.includes(:customer, lines: :product_spec).search(nil)
    counts = assert_queries_count(1) { scope.window_counts }
    expected = SalesOrder::WINDOWS.keys.index_with { |window| SalesOrder.in_window(window).count }
    assert_equal expected, counts
    assert_equal 1, counts["overdue"]
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
