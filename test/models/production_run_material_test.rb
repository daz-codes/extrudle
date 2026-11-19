require "test_helper"

class ProductionRunMaterialTest < ActiveSupport::TestCase
  include ScheduleTestHelper
  include MaterialTestHelper

  setup do
    @run = start_run
    @jade = bag(materials(:jade), bag_no: "939")
  end

  # Loading ------------------------------------------------------------------

  test "a bag is found by its code, typed in any case, and goes on its usual feed" do
    loading = ProductionRun::LoadMaterial.new(run: @run, lot_code: " #{@jade.code.downcase} ")
    assert loading.save, loading.errors.full_messages.to_sentence
    load = loading.load
    assert_equal [ @jade, "virgin_mainex", 1 ], [ load.lot, load.feed, load.from_reel_no ]
    assert_equal({ "virgin_mainex" => load }, @run.reload.current_loads)
  end

  test "usual feeds come from the material" do
    assert_equal "regrind", MaterialLoad.feed_for(materials(:regrind))
    assert_equal "pcw", MaterialLoad.feed_for(pcw_flake)
    assert_equal "virgin_coex", MaterialLoad.feed_for(capping_polymer)
    assert_equal "virgin_mainex", MaterialLoad.feed_for(materials(:jade))
  end

  test "the next bag starts at the next reel" do
    add_reels(@run, 1_000, 1_000)
    assert_equal 3, ProductionRun::LoadMaterial.new(run: @run).from_reel_no
  end

  test "unknown, emptied and off-site bags can't go on" do
    assert_load_error "L-1999-000001 isn't a lot code we know", "L-1999-000001"

    load_bag(@run, @jade)
    Stock::Reconciliation.mark_empty(@jade)
    assert_load_error "#{@jade.code} was marked empty", @jade.code

    away = bag(materials(:jade), location: "in_transit")
    assert_load_error "#{away.code} is in transit, not on site", away.code
  end

  test "a bag from storage is moved on site" do
    stored = bag(materials(:regrind), location: "storage")
    load_bag(@run, stored)
    assert stored.reload.on_site?
    assert_equal "Loaded on line D1", stored.movements.last.note
  end

  test "the bag it replaces is marked empty, unless it isn't" do
    load_bag(@run, @jade)
    second = bag(materials(:jade))
    load_bag(@run, second, from_reel_no: 5)
    assert @jade.reload.emptied?
    assert_not @jade.reconciled?, "waits for the log to finish"

    third = bag(materials(:jade))
    load_bag(@run, third, from_reel_no: 8, previous_empty: false)
    assert_not second.reload.emptied?
  end

  test "a bag can't be on two feeds, or on another line, except the shared Co-Ex feed" do
    load_bag(@run, @jade)
    assert_load_error "#{@jade.code} is already on Virgin Main-Ex", @jade.code
    assert_load_error "#{@jade.code} is on line D1 Virgin Main-Ex. Mark it empty or load another bag there first", @jade.code, feed: "pcw"

    other = start_run(stock_order_line, line: lines(:d2))
    assert_load_error "#{@jade.code} is on line D1 Virgin Main-Ex. Mark it empty or load another bag there first", @jade.code, run: other

    capping = bag(capping_polymer)
    load_bag(@run, capping)
    load_bag(other, capping)
    assert_equal capping, other.reload.current_loads["virgin_coex"].lot
  end

  test "a finished log takes no more bags" do
    load_bag(@run, @jade)
    add_reels(@run, 1_000)
    finish_cleanly(@run)
    assert_load_error "Despatch #{@run.despatch_number} is finished, so its materials can't change", bag(materials(:jade)).code
  end

  # Reel ranges --------------------------------------------------------------

  test "a bag feeds until the next bag on the same feed" do
    first = load_bag(@run, @jade)
    add_reels(@run, 1_000, 1_000, 1_000, 1_000)
    second = load_bag(@run, bag(materials(:jade)))
    regrind = load_bag(@run, bag(materials(:regrind)), from_reel_no: 3)
    add_reels(@run, 1_000, 1_000)

    assert_equal 1..4, @run.reel_range(first)
    assert_equal (5..), @run.reel_range(second)
    assert_equal (3..), @run.reel_range(regrind)
    finish_cleanly(@run)
    assert_equal 5..6, @run.reload.reel_range(@run.material_loads.find(second.id))
  end

  # Allocation ---------------------------------------------------------------

  test "output is split by recipe, then across a feed's bags by the reels they fed, to the gram" do
    product_specs(:bf_700).recipe.update("virgin_coex" => "15", "virgin_mainex" => "50", "pcw" => "25", "regrind" => "10")
    capping, flake, regrind = bag(capping_polymer), bag(pcw_flake), bag(materials(:regrind))
    [ @jade, capping, flake, regrind ].each { load_bag(@run, _1) }
    add_reels(@run, "1,000.001", "1,000.001", "1,000.001")
    jade_two = bag(materials(:jade))
    load_bag(@run, jade_two)
    add_reels(@run, "1,000.001")

    use = @run.reload.material_use
    assert_equal({ "virgin_coex" => 600_001, "virgin_mainex" => 2_000_002, "pcw" => 1_000_001, "regrind" => 400_000 }, use.feed_totals)
    assert_equal 4_000_004, use.total_g
    assert_equal({ @jade => 1_500_002, jade_two => 500_000, capping => 600_001, flake => 1_000_001, regrind => 400_000 }, use.by_lot)
  end

  # The only bag recorded, so Main-Ex takes the whole output.
  test "the first bag on a feed covers reels made before it was written down" do
    add_reels(@run, 1_000, 1_000)
    load_bag(@run, @jade)
    assert_equal({ @jade => 2_000_000 }, @run.reload.material_use.by_lot)
  end

  test "a feed in the recipe with no bag recorded hands its share to the others" do
    load_bag(@run, @jade)
    add_reels(@run, 1_000)
    use = @run.reload.material_use
    assert_equal %w[ virgin_coex pcw regrind ], use.missing_feeds
    assert_equal({ "virgin_mainex" => 1_000_000 }, use.feed_totals)
  end

  # Finishing ----------------------------------------------------------------

  test "a log can't finish without its bags" do
    assert_includes @run.finish_problems, "Record the material bags loaded"
  end

  test "finishing takes the material used off stock, against the run" do
    load_bag(@run, @jade)
    add_reels(@run, 400)
    finish_cleanly(@run)

    issue = @run.consumptions.sole
    assert_equal [ @jade, -400_000 ], [ issue.lot, issue.quantity_g ]
    assert_equal 600_000, @jade.reload.quantity_g
    assert_equal 400_000, @jade.used_g
  end

  test "bags still on the feeds carry over to the line's next log from reel 1" do
    load_bag(@run, @jade)
    emptied = bag(materials(:regrind))
    load_bag(@run, emptied)
    add_reels(@run, 400)
    Stock::Reconciliation.mark_empty(emptied)
    finish_cleanly(@run)

    following = start_run(stock_order_line)
    carried = following.material_loads.sole
    assert_equal [ @jade, "virgin_mainex", 1, true ], [ carried.lot, carried.feed, carried.from_reel_no, carried.carried_over? ]
  end

  # Reconciliation -----------------------------------------------------------

  test "a bag marked empty is reconciled when its last log finishes" do
    load_bag(@run, @jade)
    add_reels(@run, 900)
    Stock::Reconciliation.mark_empty(@jade)
    assert_equal [ @run ], Stock::Reconciliation.waiting_on(@jade).to_a
    assert_not @jade.reload.reconciled?

    finish_cleanly(@run)
    @jade.reload
    assert @jade.reconciled?
    assert_equal 0, @jade.quantity_g
    variance = @jade.movements.last
    assert_equal [ "adjustment", -100_000, Stock::Reconciliation::NOTE ], [ variance.kind, variance.quantity_g, variance.note ]

    row = Stock::Variance.new.reconciled.sole
    assert_equal [ 1_000_000, 900_000, -100_000, -1_000 ], [ row.in_g, row.used_g, row.variance_g, row.variance_bp ]
    assert row.flagged?
  end

  test "a bag used more than it held is reconciled upwards" do
    small = bag(materials(:jade), kg: 300)
    load_bag(@run, small)
    add_reels(@run, 1_000)
    finish_cleanly(@run)
    Stock::Reconciliation.mark_empty(small)
    assert_equal 700_000, small.movements.last.quantity_g
    assert_equal 0, small.reload.quantity_g
  end

  test "a bag whose logs have all finished is reconciled straight away, and can't be unmarked after" do
    load_bag(@run, @jade)
    add_reels(@run, 900)
    finish_cleanly(@run)
    Stock::Reconciliation.mark_empty(@jade)
    assert @jade.reload.reconciled?
    assert_equal 0, @jade.quantity_g
    assert_raises(ArgumentError) { Stock::Reconciliation.unmark_empty(@jade) }
  end

  test "an empty bag waiting on a log can be unmarked" do
    load_bag(@run, @jade)
    Stock::Reconciliation.mark_empty(@jade)
    Stock::Reconciliation.unmark_empty(@jade)
    assert_not @jade.reload.emptied?
  end

  test "a bag that has never been on a line can't be marked empty" do
    error = assert_raises(ArgumentError) { Stock::Reconciliation.mark_empty(@jade) }
    assert_match "hasn't been on a line", error.message
    assert_not @jade.reload.emptied?
  end

  test "the variance is found by its flag, not its note" do
    load_bag(@run, @jade)
    add_reels(@run, 900)
    Stock::Reconciliation.mark_empty(@jade)
    finish_cleanly(@run)
    variance = @jade.movements.reload.last
    assert variance.bag_variance?
    StockMovement.where(id: variance.id).update_all(note: "Reworded later")
    assert_equal(-100_000, Stock::Variance.new.reconciled.sole.variance_g)
  end

  # Mistakes and carry-over --------------------------------------------------

  test "removing a bag scanned by mistake puts the bag before it back on the feed" do
    load_bag(@run, @jade)
    wrong = load_bag(@run, bag(materials(:jade)))
    assert @jade.reload.emptied?

    @run.reload.material_loads.find(wrong.id).remove!
    assert_not @jade.reload.emptied?
    assert_equal @jade, @run.reload.current_loads.fetch("virgin_mainex").lot
  end

  test "removing a bag leaves the bag before it empty if it was already marked empty" do
    load_bag(@run, @jade)
    Stock::Reconciliation.mark_empty(@jade)
    next_bag = load_bag(@run, bag(materials(:jade)))
    assert_not next_bag.marked_previous_empty?

    @run.reload.material_loads.find(next_bag.id).remove!
    assert @jade.reload.emptied?
  end

  test "bags don't carry over once they're on the other line or off site" do
    pcw = bag(pcw_flake)
    load_bag(@run, @jade)
    load_bag(@run, pcw)
    add_reels(@run, 900)
    finish_cleanly(@run)

    other_line = start_run(stock_order_line, line: lines(:d2))
    load_bag(other_line, @jade)
    Stock::Transfer.call(pcw.reload, to: "storage")

    following = start_run(stock_order_line)
    assert_empty following.material_loads
  end

  private
    def assert_load_error(message, code, run: @run, feed: nil)
      loading = ProductionRun::LoadMaterial.new(run:, lot_code: code, feed:)
      assert_not loading.save
      assert_includes loading.errors.full_messages.map { _1.delete_prefix("Lot code ") }, message
    end
end
