require "test_helper"

class PlannerHelperTest < ActionView::TestCase
  include ScheduleTestHelper

  test "hours as the paper plan writes them" do
    assert_equal [ "10", "10½", "½", "0", "26" ], [ 600, 630, 30, 0, 1_560 ].map { print_hours(_1) }
  end

  test "the drag queue leaves out locked blocks and marks jobs nothing can pass" do
    travel_to at(MONDAY_6AM)
    editor = Schedule::Editor.new(lines(:d1))
    started = editor.add_job(sales_order_lines(:bf_open_700), planned_g: 1_900_000, starts_at: at(MONDAY_6AM))
    queued = editor.add(block("no_orders", 60))
    editor.add(block("planned_maintenance", 60, locked: true, starts_at: at("2026-11-18 06:00")))
    assert ProductionRun::Start.new(schedule_block: started).tap { _1.user = users(:floor) }.save

    queue = drag_queue(lines(:d1).schedule_blocks.ordered.to_a)
    assert_equal [ started.id, queued.id ], queue.map { _1[:id] }
    assert_equal "has started", queue.first[:stuck]
    assert_not queue.last.key?(:stuck)
  ensure
    travel_back
  end
end
