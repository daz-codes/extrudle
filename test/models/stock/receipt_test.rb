require "test_helper"

class Stock::ReceiptTest < ActiveSupport::TestCase
  def receipt(line: purchase_order_lines(:albion_jade), **attrs)
    Stock::Receipt.new(purchase_order_line: line, quantity: "1,100", **attrs)
  end

  test "each bag becomes a lot with a receipt movement, and the bags add up exactly" do
    r = receipt(quantity: "1,000", bags: 3, first_bag_no: "939", supplier_lot_ref: "B1", delivery_ref: "DN1", location: "storage")
    r.user = users(:office)
    assert r.save, r.errors.full_messages.to_sentence

    assert_equal %w[ L-2026-000004 L-2026-000005 L-2026-000006 ], r.lots.map(&:code)
    assert_equal [ 333_334, 333_333, 333_333 ], r.lots.map(&:initial_g)
    assert_equal %w[ 939 940 941 ], r.lots.map(&:bag_no)
    assert r.lots.all? { _1.storage? && _1.supplier_lot_ref == "B1" && _1.material == materials(:jade) }
    movement = r.lots.first.movements.sole
    assert_equal [ "receipt", 333_334, "storage", users(:office) ], [ movement.kind, movement.quantity_g, movement.to_location, movement.user ]
  end

  test "tonnes, and bag numbers with letters" do
    r = receipt(quantity: "2.2", quantity_unit: "t", bags: 2, first_bag_no: "A9")
    assert r.save
    assert_equal [ 1_100_000, 1_100_000 ], r.lots.map(&:initial_g)
    assert_equal %w[ A9 B0 ], r.lots.map(&:bag_no)
  end

  test "a part delivery makes the PO part received, the rest makes it received" do
    po = purchase_orders(:albion_sent) # 1,100 kg of JADE
    assert receipt(quantity: "600").save
    assert po.reload.part_received?
    assert_equal 600_000, purchase_order_lines(:albion_jade).received_g

    assert receipt(quantity: "500").save
    assert po.reload.received?
  end

  test "over-deliveries are allowed and complete the line" do
    assert receipt(quantity: "1,150").save
    assert purchase_orders(:albion_sent).reload.received?
  end

  test "only sent or part-received POs can be received against" do
    r = receipt(line: purchase_order_lines(:pacific_jade))
    assert_not r.save
    assert_match "is draft", r.errors[:base].first
  end

  test "opening stock and regrind need no PO" do
    r = Stock::Receipt.new(material_id: materials(:regrind).id, quantity: "740", bags: 1)
    assert r.save, r.errors.full_messages.to_sentence
    assert_nil r.lots.sole.purchase_order_line
    assert_equal 740_000, r.lots.sole.quantity_g
  end

  test "validates the weight, bag count and location" do
    assert_not Stock::Receipt.new(quantity: "1").valid?
    assert receipt(quantity: "lots").tap(&:validate).errors.of_kind?(:quantity, :not_a_number)
    assert_not receipt(bags: 0).valid?
    assert_not receipt(bags: 101).valid?
    assert_not receipt(location: "moon").valid?
    assert receipt(quantity: "0.002", bags: 3).tap(&:validate).errors[:quantity].first.include?("too small")
  end

  test "nothing is saved if a lot fails" do
    materials(:jade).update_columns(active: false)
    assert_no_difference -> { Lot.count } do
      assert_not receipt.save
    end
  end
end
