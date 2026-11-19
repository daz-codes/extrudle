require "test_helper"

class DeliveryNoteTest < ActiveSupport::TestCase
  include ScheduleTestHelper
  include DispatchTestHelper

  setup do
    @order_line = sales_order_lines(:bf_open_700) # 10 t
    @order = @order_line.sales_order
    @order_line.product_spec.update_columns(reels_per_pallet: 2)
  end

  test "pallets come from the reels' pallet numbers, and are ready once a later pallet has started" do
    run = run_with_pallets(pallets: [ [ 500, 500 ], [ 400 ] ])
    one, two = run.pallets
    assert_equal [ "#{run.despatch_number}/1", 1_000_000, [ 1, 2 ] ], [ one.label, one.weight_g, one.reel_numbers ]
    assert one.complete?
    assert_not two.complete?, "the last pallet of a running log may still be filling"
    assert_equal [ one ], @order.pallets_to_dispatch

    run.update_columns(status: "finished")
    assert_equal [ one, two ], @order.reload.pallets_to_dispatch
  end

  test "a pallet holding the spec's reels per pallet is ready" do
    @order_line.product_spec.update_columns(reels_per_pallet: 1)
    run = run_with_pallets(pallets: [ [ 500 ] ])
    assert run.pallets.sole.complete?
    @order_line.product_spec.update_columns(reels_per_pallet: nil)
    assert_not ProductionRun.find(run.id).pallets.sole.complete?, "no reels per pallet: wait for the next pallet or the end"
  end

  test "a pallet goes out once, and its reels are fixed from then on" do
    run = run_with_pallets(pallets: [ [ 500, 500 ], [ 400 ] ])
    note = delivery_note_for(run, [ 1 ])
    assert_equal [ 1 ], note.note_pallets.map(&:pallet_no)
    assert_empty @order.pallets_to_dispatch

    other = @order.delivery_notes.create!
    assert_raises(ActiveRecord::RecordInvalid) { other.set_pallets!([ [ run.id, 1 ] ]) }

    reel = run.reels.first
    reel.weight_kg = "450"
    assert_not reel.save
    assert_includes reel.errors.full_messages, "Pallet 1 is on a delivery note, so its reels can't change"
    assert reel.reload.update(initials: "DH"), "other details can still be corrected"
    assert_not run.reels.first.destroy
    assert_not run.reels.create(weight_kg: "300", pallet_no: 1).persisted?
  end

  test "the next reel goes on a new pallet once the current one is on a note" do
    run = run_with_pallets(pallets: [ [ 500 ] ])
    run.update_columns(status: "finished")
    delivery_note_for(run.reload, [ 1 ])
    run.update_columns(status: "running")
    assert_equal 2, run.reload.suggested_pallet_no
  end

  test "lines group pallets by order line and value them at the price per tonne, to the penny" do
    @order_line.update_columns(price_per_tonne_cents: 165_050)
    run = run_with_pallets(pallets: [ [ "500.003", 500 ], [ 400 ] ], finish: true)
    line = delivery_note_for(run, [ 1, 2 ]).lines.sole
    assert_equal [ 1_400_003, 3, 2 ], [ line.weight_g, line.reel_count, line.pallets.size ]
    assert_equal 231_070, line.net_cents # 1.400003 t × £1,650.50 = £2,310.704…
  end

  test "dispatching sets the order dispatched once every line has gone in full, and undo puts it back" do
    @order_line.update_columns(quantity_g: 1_400_000)
    run = run_with_pallets(pallets: [ [ 500, 500 ], [ 400 ] ], finish: true)
    first = delivery_note_for(run, [ 1 ], dispatch: true)
    assert @order.reload.in_production?

    second = delivery_note_for(run, [ 2 ])
    assert_raises(ArgumentError) { second.mark_dispatched!(on: Date.current + 1) }
    second.mark_dispatched!(user: users(:office))
    assert @order.reload.dispatched?
    assert_equal [ Date.current, users(:office) ], [ second.dispatched_on, second.dispatched_by ]

    second.undo_dispatch!
    assert @order.reload.in_production?
    assert first.reload.dispatched?
  end

  test "an order that went out short is closed by hand" do
    run = run_with_pallets(pallets: [ [ 500, 500 ], [ 400 ] ], finish: true)
    assert_raises(ArgumentError) { @order.reload.mark_dispatched! }
    delivery_note_for(run, [ 1, 2 ], dispatch: true)
    assert @order.reload.in_production?, "1.4 t of 10 t"
    @order.mark_dispatched!
    assert @order.dispatched?
  end

  test "a note needs a pallet to be dispatched, and a dispatched note's pallets can't change" do
    note = @order.delivery_notes.create!
    assert_raises(ArgumentError) { note.mark_dispatched! }
    run = run_with_pallets(finish: true)
    note.set_pallets!([ [ run.id, 1 ] ])
    note.mark_dispatched!
    assert_raises(ArgumentError) { note.set_pallets!([ [ run.id, 2 ] ]) }
  end

  test "numbered DN-00001 onwards" do
    assert_equal "DN-00001", @order.delivery_notes.create!.number
    assert_equal "DN-00002", @order.delivery_notes.create!.number
  end

  test "a note can't be dispatched with nowhere to deliver to" do
    run = run_with_pallets(finish: true)
    run.sales_order.customer.update!(address: nil)
    note = delivery_note_for(run, [ 1 ])
    error = assert_raises(ArgumentError) { note.mark_dispatched! }
    assert_equal "Add a delivery address first", error.message

    note.update!(delivery_address: "Gate 3, Leeds")
    note.mark_dispatched!
    assert note.dispatched?
  end
end
