require "test_helper"

class RunCheckTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  setup do
    start = ProductionRun::Start.new(schedule_block: planned_job)
    assert start.save
    @run = start.run # bf_700: 700 mm × 250 µm
  end

  test "thickness tolerance is ±5%, rounded inwards to whole microns" do
    assert_equal [ 250, 238, 262 ], ProductionRun::Checklist.range("thickness", product_specs(:bf_700))
    assert_equal [ 700, 698, 702 ], ProductionRun::Checklist.range("width", product_specs(:bf_700))
  end

  test "readings are judged against the target when recorded, and keep it" do
    good = @run.record_measurement(stage: "startup", item: "thickness", actual: "262", user: users(:floor))
    assert good.persisted?
    assert good.passed?
    assert_equal [ 250, 238, 262, "µm" ], [ good.target, good.min_value, good.max_value, good.unit ]

    bad = @run.record_measurement(stage: "startup", item: "width", actual: "697")
    assert_not bad.passed?
    assert_equal(-3, bad.difference)

    product_specs(:bf_700).update_columns(width_mm: 697)
    assert_not bad.reload.passed?
    assert_equal 700, bad.target
  end

  test "thickness can be typed as on the paper plan" do
    assert_equal 252, RunCheck.parse_reading("thickness", ".252")
    assert_equal 252, RunCheck.parse_reading("thickness", "0.252")
    assert_equal 252, RunCheck.parse_reading("thickness", "252")
    assert_equal 700, RunCheck.parse_reading("width", "700")
    assert_raises(ArgumentError) { RunCheck.parse_reading("thickness", ".2525") }
    assert_raises(ArgumentError) { RunCheck.parse_reading("width", "700.5") }
    assert_raises(ArgumentError) { RunCheck.parse_reading("width", "") }
  end

  test "bad readings aren't saved" do
    check = @run.record_measurement(stage: "startup", item: "width", actual: "wide")
    assert_not check.persisted?
    assert_includes check.errors[:actual], "is not a number"
    assert_not @run.record_measurement(stage: "startup", item: "width", actual: "0").persisted?
    assert_equal 0, @run.checks.count
  end
end
