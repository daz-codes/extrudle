require "test_helper"

class LotTest < ActiveSupport::TestCase
  test "weight is the sum of its movements" do
    assert_equal 1_000_000, lots(:jade_opening).quantity_g
    assert_equal 0, lots(:jade_used_up).quantity_g
    assert lots(:jade_used_up).empty?
    assert_equal 500_000, Lot.with_quantity.find(lots(:regrind_bag).id).quantity_g
  end

  test "in stock leaves out used-up lots" do
    assert_equal %w[ L-2026-000001 L-2026-000002 ], Lot.in_stock.by_code.pluck(:code)
  end

  test "codes count up within the year" do
    assert_equal %w[ L-2026-000004 L-2026-000005 ], Lot.next_codes(2, year: 2026)
    assert_equal %w[ L-2027-000001 ], Lot.next_codes(1, year: 2027)
    lots(:jade_opening).update_columns(code: "L-2026-999999")
    assert_equal %w[ L-2026-1000000 ], Lot.next_codes(1, year: 2026)
  end

  test "material must match the PO line" do
    lot = Lot.new(code: "L-2026-000100", material: materials(:regrind), purchase_order_line: purchase_order_lines(:albion_jade),
                  received_on: Date.current, initial_g: 1)
    assert_not lot.valid?
    assert lot.errors.include?(:material)
  end

  test "movements can't be edited or deleted" do
    movement = stock_movements(:jade_opening_receipt)
    assert_raises(ActiveRecord::ReadOnlyRecord) { movement.update!(quantity_g: 5) }
    assert_raises(ActiveRecord::ReadOnlyRecord) { movement.destroy }
  end

  test "transfers carry no weight; other movements must" do
    lot = lots(:jade_opening)
    assert_not lot.movements.build(kind: "transfer", quantity_g: 10).valid?
    assert_not lot.movements.build(kind: "adjustment", quantity_g: 0).valid?
    assert_not lot.movements.build(kind: "receipt", quantity_g: -5).valid?
    assert lot.movements.build(kind: "adjustment", quantity_g: -5).valid?
  end
end
