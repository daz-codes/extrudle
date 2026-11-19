require "test_helper"

class ReelTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  setup do
    start = ProductionRun::Start.new(schedule_block: planned_job)
    assert start.save
    @run = start.run # bf_700, 10,000 kg ordered, max reel 1,100 kg
  end

  def add(weight_kg = "1,050", **attrs)
    @run.reels.create!(weight_kg:, **attrs)
  end

  test "reels are numbered in order, timed now and weighed in grams" do
    freeze_time do
      first = add("1,042.5")
      assert_equal [ 1, 1_042_500, Time.current ], [ first.reel_no, first.weight_g, first.produced_at ]
    end
    assert_equal 2, add.reel_no
    assert_equal 3, @run.next_reel_no
  end

  test "running total and whole percent of the order" do
    add("1,042.5")
    add("1,061")
    @run.reels.reset
    assert_equal 2_103_500, @run.total_g
    assert_equal 21, @run.percent_of_order # 21.035% rounds down
  end

  test "weights must be positive grams; length and pallet are optional whole numbers" do
    assert_not @run.reels.build(weight_kg: "0").valid?
    assert_not @run.reels.build(weight_kg: "heavy").valid?
    assert_not @run.reels.build(weight_kg: "1.0005").valid?
    assert_not @run.reels.build(weight_kg: "1000", length_m: 0).valid?
    assert @run.reels.build(weight_kg: "1000", length_m: nil, pallet_no: nil).valid?
  end

  test "over the spec's max reel weight is a warning, not an error" do
    heavy = add("1,150")
    assert heavy.over_max_weight?
    assert_not add("1,100").over_max_weight?
  end

  test "the next reel's pallet follows reels per pallet, one per pallet by default" do
    assert_equal 1, @run.suggested_pallet_no
    add(pallet_no: 1)
    @run.reels.reset
    assert_equal 2, @run.suggested_pallet_no

    product_specs(:bf_700).update_columns(reels_per_pallet: 2)
    @run.product_spec.reload
    assert_equal 1, @run.suggested_pallet_no
    add(pallet_no: 1)
    @run.reels.reset
    assert_equal 2, @run.suggested_pallet_no
  end

  test "the next reel form carries over pallet and initials, and stays out of the totals" do
    add(pallet_no: 1, initials: " dh ")
    @run.reels.reset
    reel = @run.build_next_reel
    assert_equal [ 2, 2, "DH" ], [ reel.reel_no, reel.pallet_no, reel.initials ]
    assert_equal 1, @run.reels.size
  end

  test "reels can't change once the log is finished" do
    reel = add
    @run.update_columns(status: "finished")
    reel.reload.weight_kg = "900"
    assert_not reel.valid?
    assert_not @run.reload.reels.build(weight_kg: "900").valid?
  end
end
