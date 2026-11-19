require "test_helper"

class Stock::TransferAndAdjustmentTest < ActiveSupport::TestCase
  test "a transfer moves whole lots and records where from and to" do
    lot = lots(:jade_opening)
    moved = Stock::Transfer.call([ lot, lots(:regrind_bag) ], to: "storage", user: users(:office), note: "Full by the line")

    assert_equal [ lot ], moved # regrind was already in storage
    assert lot.reload.storage?
    movement = lot.movements.last
    assert_equal [ "transfer", 0, "on_site", "storage", "Full by the line" ],
                 [ movement.kind, movement.quantity_g, movement.from_location, movement.to_location, movement.note ]
    assert_equal 1_000_000, lot.quantity_g
  end

  test "a transfer needs a real location" do
    assert_raises(Stock::Transfer::Error) { Stock::Transfer.call(lots(:jade_opening), to: "moon") }
  end

  test "an adjustment posts the difference to the counted weight" do
    lot = lots(:jade_opening)
    adjustment = Stock::Adjustment.new(lot:, counted_kg: "992.5", reason: "Reweighed")
    adjustment.user = users(:office)
    assert adjustment.save
    assert_equal(-7_500, adjustment.movement.quantity_g)
    assert_equal 992_500, lot.reload.quantity_g

    assert Stock::Adjustment.new(lot: lot.reload, counted_kg: "0", reason: "Written off").save
    assert lot.reload.empty?
  end

  test "an adjustment needs a reason, a weight and a change" do
    lot = lots(:jade_opening)
    assert_not Stock::Adjustment.new(lot:, counted_kg: "900").valid?
    assert_not Stock::Adjustment.new(lot:, counted_kg: "", reason: "x").valid?
    assert_not Stock::Adjustment.new(lot:, counted_kg: "-1", reason: "x").valid?
    assert_not Stock::Adjustment.new(lot:, counted_kg: "lots", reason: "x").valid?
    same = Stock::Adjustment.new(lot:, counted_kg: "1000", reason: "x")
    assert_not same.valid?
    assert same.errors.include?(:counted_kg)
  end
end
