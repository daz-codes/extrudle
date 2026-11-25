require "test_helper"

# Goods in on the floor (Slice 12).
class Floor::DeliveriesControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:floor) }

  test "the floor home links to goods in" do
    get floor_root_path
    assert_select "a[href=?]", floor_deliveries_path, text: "Goods in"
  end

  test "lists deliveries still to come in, with weights but no prices (Q82)" do
    get floor_deliveries_path
    assert_response :success
    assert_select "#purchase_order_#{purchase_orders(:albion_sent).id}", /Albion.*PO-00002.*JADE.*0 kg of 1,100 kg in/m
    assert_select "#purchase_order_#{purchase_orders(:pacific_draft).id}", count: 0
    assert_select "#purchase_order_#{purchase_orders(:albion_received).id}", count: 0
    assert_no_match(/1,185|£|USD|CIF|DAP/, response.body)
  end

  test "receive a delivery on the floor, then print its labels (Q81)" do
    order = purchase_orders(:albion_sent)
    line = purchase_order_lines(:albion_jade)
    get floor_delivery_path(order)
    assert_select "a[href=?]", new_purchase_order_receipt_path(order), text: "Receive goods"

    get new_purchase_order_receipt_path(order)
    assert_response :success
    assert_select "header .badge", "Floor"
    assert_select "a[href=?]", floor_delivery_path(order), text: "Cancel"

    assert_difference -> { Lot.count } => 2 do
      post purchase_order_receipts_path(order), params: { receipt: {
        purchase_order_line_id: line.id, quantity_unit: "kg", quantity: "1,100", bags: "2",
        received_on: Date.current, location: "on_site" } }
    end
    assert_redirected_to floor_delivery_path(order)
    assert_equal users(:floor), StockMovement.last.user

    follow_redirect!
    lots = Lot.where(purchase_order_line: line).by_code
    assert_select "section[aria-labelledby=received_today] tbody tr", count: 2
    assert_select "a[href=?]", labels_lots_path(ids: lots.map(&:id)), text: "Print labels"
    assert_select "p", /received, so nothing more can be received/

    get labels_lots_path(ids: lots.map(&:id))
    assert_response :success
  end

  test "a received or draft order can't be received against from the floor" do
    order = purchase_orders(:pacific_draft)
    get new_purchase_order_receipt_path(order)
    assert_redirected_to floor_delivery_path(order)
  end

  test "the rest of stock and purchasing stays office only" do
    [ lots_path, new_lot_path, purchase_order_path(purchase_orders(:albion_sent)) ].each do |path|
      get path
      assert_redirected_to floor_root_path
    end
  end
end
