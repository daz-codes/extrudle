require "test_helper"

class PurchaseOrdersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:office) }

  test "floor users are kept out" do
    sign_out
    sign_in_as users(:floor)
    get purchase_orders_path
    assert_redirected_to floor_root_path
  end

  test "index shows open POs by expected date and flags overdue ones" do
    get purchase_orders_path
    assert_response :success
    assert_select "a", text: "PO-00001"
    assert_select "a", text: "PO-00003", count: 0
    assert_select "tr#purchase_order_#{purchase_orders(:albion_sent).id}", /overdue/
  end

  test "index filters by status, supplier and search" do
    get purchase_orders_path(status: "received")
    assert_select "a", text: "PO-00003"
    assert_select "tbody tr", 1

    get purchase_orders_path(supplier: suppliers(:pacific).id)
    assert_select "a", text: "PO-00001"
    assert_select "a", text: "PO-00002", count: 0

    get purchase_orders_path(q: "oc-1182")
    assert_select "a", text: "PO-00002"
    assert_select "a", text: "PO-00001", count: 0
  end

  test "create a PO, then add a line in tonnes" do
    assert_difference "PurchaseOrder.count" do
      post purchase_orders_path, params: { purchase_order: { supplier_id: suppliers(:pacific).id, expected_on: Date.current + 20, supplier_ref: " q-9 " } }
    end
    order = PurchaseOrder.order(:id).last
    assert_redirected_to purchase_order_path(order)
    assert_equal [ "PO-00004", "USD", "CIF", "q-9" ], [ order.number, order.currency, order.incoterm, order.supplier_ref ]

    post purchase_order_lines_path(order), params: { purchase_order_line: {
      material_id: materials(:jade).id, quantity_unit: "t", quantity: "44", price_per_tonne: "1,240.50" } }
    assert_redirected_to purchase_order_path(order)
    line = order.lines.sole
    assert_equal [ 44_000_000, 124_050 ], [ line.quantity_g, line.price_per_tonne_cents ]

    get purchase_order_path(order)
    assert_select "td", text: "$54,582.00"
  end

  test "an invalid line re-renders the PO with errors" do
    order = purchase_orders(:pacific_draft)
    post purchase_order_lines_path(order), params: { purchase_order_line: { material_id: materials(:jade).id, quantity: "lots", price_per_tonne: "" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Quantity is not a number/
    assert_equal 1, order.lines.count
  end

  test "currency and supplier can't change once there are lines" do
    order = purchase_orders(:pacific_draft)
    patch purchase_order_path(order), params: { purchase_order: { currency: "GBP", supplier_id: suppliers(:albion).id, incoterm: "fob" } }
    assert_redirected_to purchase_order_path(order)
    order.reload
    assert_equal [ "USD", suppliers(:pacific), "FOB" ], [ order.currency, order.supplier, order.incoterm ]
  end

  test "sent POs can't be edited until they go back to draft" do
    order = purchase_orders(:albion_sent)
    get edit_purchase_order_path(order)
    assert_redirected_to purchase_order_path(order)

    patch purchase_order_line_path(order, purchase_order_lines(:albion_jade)), params: { purchase_order_line: { quantity: "1" } }
    assert_redirected_to purchase_order_path(order)
    assert_equal 1_100_000, purchase_order_lines(:albion_jade).reload.quantity_g

    patch back_to_draft_purchase_order_path(order)
    assert order.reload.draft?
    patch purchase_order_line_path(order, purchase_order_lines(:albion_jade)), params: { purchase_order_line: { quantity: "1" } }
    assert_equal 1_000, purchase_order_lines(:albion_jade).reload.quantity_g
  end

  test "mark sent, cancel and reopen" do
    order = purchase_orders(:pacific_draft)
    patch mark_sent_purchase_order_path(order)
    assert_redirected_to purchase_order_path(order)
    assert order.reload.sent?

    patch mark_sent_purchase_order_path(order)
    assert_equal "Only draft purchase orders can be sent", flash[:alert]

    patch cancel_purchase_order_path(order)
    assert order.reload.cancelled?
    patch reopen_purchase_order_path(order)
    assert order.reload.draft?
  end

  test "remove a line from a draft" do
    order = purchase_orders(:pacific_draft)
    assert_difference "order.lines.count", -1 do
      delete purchase_order_line_path(order, purchase_order_lines(:pacific_jade))
    end
  end

  test "the PDF downloads, marked as a draft until sent" do
    get purchase_order_path(purchase_orders(:pacific_draft), format: :pdf)
    assert_response :success
    assert_equal "application/pdf", response.media_type
    assert_match "PO-00001-draft.pdf", response.headers["Content-Disposition"]
    assert response.body.start_with?("%PDF")

    get purchase_order_path(purchase_orders(:albion_sent), format: :pdf)
    assert_match "PO-00002.pdf", response.headers["Content-Disposition"]
  end
end
