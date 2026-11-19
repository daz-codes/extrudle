require "test_helper"

class ProductionRunFinishTest < ActiveSupport::TestCase
  include ScheduleTestHelper
  include MaterialTestHelper

  setup do
    start = ProductionRun::Start.new(schedule_block: planned_job)
    assert start.save
    @run = start.run
  end

  def complete_end_of_run(width: "700", thickness: "250")
    load_bag(@run, lots(:jade_opening))
    @run.reels.create!(weight_kg: "1,050")
    @run.record_measurement(stage: "end_of_run", item: "width", actual: width)
    @run.record_measurement(stage: "end_of_run", item: "thickness", actual: thickness)
    ProductionRun::Checklist.items("line_clearance").each_key { @run.record_check(stage: "line_clearance", item: _1, passed: true) }
    @run.reload
  end

  test "lists what's missing before a log can be finished" do
    problems = @run.finish_problems
    assert_includes problems, "Enter at least one reel"
    assert_includes problems, "Record the end-of-run width"
    assert_includes problems, "Line clearance: line cleared for the next micron"
    assert_raises(ProductionRun::NotFinishable) { @run.finish!(user: users(:floor)) }
  end

  test "start-up readings don't count as end-of-run readings" do
    @run.record_measurement(stage: "startup", item: "width", actual: "700")
    assert_includes @run.reload.finish_problems, "Record the end-of-run width"
  end

  test "finishes once reels, end readings and line clearance are done" do
    complete_end_of_run
    assert_empty @run.finish_problems
    freeze_time do
      @run.finish!(user: users(:floor))
      assert @run.finished?
      assert_equal [ Time.current, users(:floor) ], [ @run.ended_at, @run.finished_by ]
    end
    assert_raises(ProductionRun::NotFinishable) { @run.finish! }
  end

  test "a clearance answered No stops it finishing" do
    complete_end_of_run
    @run.record_check(stage: "line_clearance", item: "materials_cleared", passed: false)
    assert_includes @run.reload.finish_problems, "Line clearance: materials cleared from the line"
  end

  test "an out-of-tolerance end reading needs a comment" do
    complete_end_of_run(thickness: ".270")
    assert @run.out_of_tolerance_at_end?
    assert_equal [ "An end-of-run reading is out of tolerance: add a comment or corrective action" ], @run.finish_problems

    @run.update!(comments: "Gauge drifted thick on the last reel; die bolts adjusted.")
    assert_empty @run.finish_problems
    @run.finish!
  end

  test "a finished line can start its next log" do
    complete_end_of_run
    @run.finish!
    other = ProductionRun::Start.new(schedule_block: planned_job(stock_order_line))
    assert other.save, other.errors.full_messages.to_sentence
  end
end
