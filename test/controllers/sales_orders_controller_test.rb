require "test_helper"

class SalesOrdersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:office) }

  test "floor users are kept out" do
    sign_out
    sign_in_as users(:floor)
    get sales_orders_path
    assert_redirected_to floor_root_path
  end

  test "index shows active orders by required date and flags late ones" do
    get sales_orders_path
    assert_response :success
    assert_select "a", text: "SO-00001"
    assert_select "a", text: "SO-00004", count: 0
    assert_select "tr#sales_order_#{sales_orders(:bf_overdue).id}", /late/
    assert_select "tr#sales_order_#{sales_orders(:bf_overdue).id} .badge", text: "Urgent"
  end

  test "index filters by window, status and search" do
    get sales_orders_path(window: "overdue")
    assert_select "tbody tr", 1

    get sales_orders_path(status: "dispatched")
    assert_select "a", text: "SO-00004"

    get sales_orders_path(q: "rhine")
    assert_select "a", text: "SO-00003"
    assert_select "a", text: "SO-00001", count: 0
  end

  test "a week order with a delivery site" do
    post sales_orders_path, params: { sales_order: { customer_id: customers(:rhine).id, required_on: "2026-12-02", required_week: "1", delivery_site: "Cinderford" } }
    order = SalesOrder.order(:id).last
    assert_equal [ Date.new(2026, 11, 30), true, "Cinderford" ], [ order.required_on, order.required_week, order.delivery_site ]

    follow_redirect!
    assert_select "p", /w\/c Mon 30 Nov 2026/
    assert_select "p", /Cinderford/
  end

  test "create then add a line in tonnes" do
    assert_difference "SalesOrder.count" do
      post sales_orders_path, params: { sales_order: { customer_id: customers(:rhine).id, customer_po_ref: "rv-1", required_on: Date.current + 10 } }
    end
    order = SalesOrder.order(:id).last
    assert_redirected_to sales_order_path(order)
    assert_equal "RV-1", order.customer_po_ref

    assert_difference "order.lines.count" do
      post sales_order_lines_path(order), params: { sales_order_line: {
        product_spec_id: product_specs(:stock).id, quantity_unit: "t", quantity: "4.5", price_per_tonne: "1,700.5" } }
    end
    line = order.lines.last
    assert_equal 4_500_000, line.quantity_g
    assert_equal 170_050, line.price_per_tonne_cents
  end

  test "adding a bad line re-renders the order with errors" do
    order = sales_orders(:rhine_later)
    post sales_order_lines_path(order), params: { sales_order_line: { product_spec_id: product_specs(:bf_700).id, quantity: "x" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /another customer/
    assert_select "[role=alert]", /Quantity is not a number/
  end

  test "edit and remove a line" do
    order = sales_orders(:bf_open)
    line = sales_order_lines(:bf_open_700)
    get edit_sales_order_line_path(order, line)
    assert_response :success

    patch sales_order_line_path(order, line), params: { sales_order_line: { quantity_unit: "kg", quantity: "8000" } }
    assert_equal 8_000_000, line.reload.quantity_g

    assert_difference "SalesOrderLine.count", -1 do
      delete sales_order_line_path(order, line)
    end
  end

  test "dispatched orders can't be edited" do
    order = sales_orders(:bf_dispatched)
    get edit_sales_order_path(order)
    assert_redirected_to sales_order_path(order)

    line = sales_order_lines(:bf_dispatched_700)
    patch sales_order_line_path(order, line), params: { sales_order_line: { quantity: "1" } }
    assert_redirected_to sales_order_path(order)
    assert_equal 4_000_000, line.reload.quantity_g
  end

  test "cancel and reopen" do
    order = sales_orders(:bf_open)
    patch cancel_sales_order_path(order)
    assert order.reload.cancelled?
    patch reopen_sales_order_path(order)
    assert order.reload.open?
  end

  test "spec summary for the line form" do
    get summary_product_spec_path(product_specs(:bf_700))
    assert_response :success
    assert_select "turbo-frame#spec_summary", /\.250/
  end
end
