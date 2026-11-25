require "test_helper"

class StockControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:office) }

  test "floor users are kept out" do
    sign_out
    sign_in_as users(:floor)
    [ stock_path, lots_path, lot_path(lots(:jade_opening)), new_lot_path, purchase_order_path(purchase_orders(:albion_sent)) ].each do |path|
      get path
      assert_redirected_to floor_root_path
    end
  end

  test "stock on hand by category, material and location" do
    get stock_path
    assert_response :success
    assert_select "tr#stock_material_#{materials(:jade).id}", /1 t/
    assert_select "tr#stock_material_#{materials(:jade).id}", /1\.1 t/ # on order
    assert_select "tr#stock_material_#{materials(:regrind).id}", /500 kg/
  end

  test "receive goods against a PO, then land on its lots ready to label" do
    order = purchase_orders(:albion_sent)
    line = purchase_order_lines(:albion_jade)
    get new_purchase_order_receipt_path(order)
    assert_response :success

    assert_difference -> { Lot.count } => 2, -> { StockMovement.count } => 2 do
      post purchase_order_receipts_path(order), params: { receipt: {
        purchase_order_line_id: line.id, quantity_unit: "kg", quantity: "1,100", bags: "2", first_bag_no: "939",
        supplier_lot_ref: "CZ-9", delivery_ref: "DN-1", received_on: Date.current, location: "on_site" } }
    end
    assert_redirected_to lots_path(po_line: line.id, received_on: Date.current)
    assert_equal "Received 2 bags of JADE as L-2026-000004 to L-2026-000005. Print their labels below.", flash[:notice]
    assert order.reload.received?
    assert_equal users(:office), StockMovement.last.user

    follow_redirect!
    assert_select "a", text: "Print 2 labels"
  end

  test "invalid goods in re-renders with errors" do
    order = purchase_orders(:albion_sent)
    post purchase_order_receipts_path(order), params: { receipt: { purchase_order_line_id: purchase_order_lines(:albion_jade).id, quantity: "", bags: "0" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Quantity/
  end

  test "a large delivery asks for confirmation, then goes through" do
    order = purchase_orders(:albion_sent)
    params = { purchase_order_line_id: purchase_order_lines(:albion_jade).id, quantity_unit: "t", quantity: "22", bags: "2",
               received_on: Date.current, location: "on_site" }
    assert_no_difference -> { Lot.count } do
      post purchase_order_receipts_path(order), params: { receipt: params }
    end
    assert_response :unprocessable_content
    assert_select "input[type=checkbox][name='receipt[confirm_large_delivery]']"

    assert_difference -> { Lot.count } => 2 do
      post purchase_order_receipts_path(order), params: { receipt: params.merge(confirm_large_delivery: "1") }
    end
  end

  test "drafts can't be received against" do
    order = purchase_orders(:pacific_draft)
    get new_purchase_order_receipt_path(order)
    assert_redirected_to purchase_order_path(order)
  end

  test "close a part-received PO short" do
    order = purchase_orders(:albion_sent)
    Stock::Receipt.new(purchase_order_line: purchase_order_lines(:albion_jade), quantity: "500").save!
    patch close_short_purchase_order_path(order)
    assert_redirected_to purchase_order_path(order)
    assert order.reload.received?
    follow_redirect!
    assert_select "p", /Closed short/
  end

  test "add stock without a PO" do
    assert_difference "Lot.count", 4 do
      post lots_path, params: { receipt: { material_id: materials(:regrind).id, quantity: "2,960", bags: "4", received_on: Date.current, location: "on_site" } }
    end
    assert_equal [ 740_000 ], Lot.last(4).map(&:initial_g).uniq
  end

  test "lot list filters, hides used-up lots unless asked" do
    get lots_path
    assert_select "a", text: "L-2026-000001"
    assert_select "a", text: "L-2026-000003", count: 0

    get lots_path(empty: "1")
    assert_select "a", text: "L-2026-000003"

    get lots_path(location: "storage")
    assert_select "tbody tr", 1
    assert_select "a", text: "L-2026-000002"

    get lots_path(q: "cz302-26")
    assert_select "a", text: "L-2026-000001"
    assert_select "a", text: "L-2026-000002", count: 0
  end

  test "lot page shows its history; moving and adjusting post movements" do
    lot = lots(:jade_opening)
    get lot_path(lot)
    assert_response :success
    assert_select "td", /Received into on site/

    patch move_lot_path(lot), params: { location: "in_transit" }
    assert_redirected_to lot_path(lot)
    assert lot.reload.in_transit?

    post lot_adjustment_path(lot), params: { stock_adjustment: { counted_kg: "990", reason: "Reweighed" } }
    assert_redirected_to lot_path(lot)
    assert_equal 990_000, lot.quantity_g

    post lot_adjustment_path(lot), params: { stock_adjustment: { counted_kg: "990", reason: "" } }
    assert_response :unprocessable_content
  end

  test "label sheet has a QR code per lot" do
    get labels_lots_path
    assert_response :success
    assert_select "article.lot-label", 2
    assert_select "article#label_lot_#{lots(:jade_opening).id} svg"
    assert_select "article#label_lot_#{lots(:jade_opening).id}", /CZ302-26-001/

    get labels_lots_path(ids: [ lots(:jade_used_up).id ])
    assert_select "article.lot-label", 1
  end
end
