require "test_helper"

class Schedule::ReflowTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  setup do
    travel_to at(MONDAY_6AM)
    @line = lines(:d1)
  end

  def flowing(kind, minutes, position)
    block(kind, minutes, line: @line, position: position)
  end

  test "lays unlocked blocks back to back from now, in queue order" do
    blocks = [ flowing("no_orders", 60, 2), flowing("changeover", 90, 1) ]
    Schedule::Reflow.new(@line, blocks: blocks).call

    assert_equal [ [ "changeover", "Mon 06:00", "Mon 07:30" ], [ "no_orders", "Mon 07:30", "Mon 08:30" ] ], timeline(@line)
    assert_equal [ 1, 2 ], @line.schedule_blocks.ordered.map(&:position)
  end

  test "starts from the next slot if now is mid-slot" do
    travel_to at("2026-11-16 06:10")
    Schedule::Reflow.new(@line, blocks: [ flowing("no_orders", 30, 1) ]).call
    assert_equal [ [ "no_orders", "Mon 06:30", "Mon 07:00" ] ], timeline(@line)
  end

  test "keeps the line's existing start when reflowing" do
    Schedule::Reflow.new(@line, blocks: [ flowing("no_orders", 60, 1) ]).call
    travel_to at("2026-11-16 09:00")
    Schedule::Reflow.new(@line).call
    assert_equal [ [ "no_orders", "Mon 06:00", "Mon 07:00" ] ], timeline(@line)
  end

  test "an explicit start re-anchors the queue" do
    Schedule::Reflow.new(@line, blocks: [ flowing("no_orders", 60, 1) ]).call
    Schedule::Reflow.new(@line, starts_at: at("2026-11-17 06:00")).call
    assert_equal [ [ "no_orders", "Tue 06:00", "Tue 07:00" ] ], timeline(@line)
  end

  test "locked blocks never move and the queue flows around them" do
    engineer = block("planned_maintenance", 120, line: @line, locked: true, starts_at: at("2026-11-16 08:00"))
    first = flowing("no_orders", 60, 1)     # 06:00–07:00 fits before the visit
    second = flowing("changeover", 90, 2)   # 07:00–08:30 would overlap, so it goes after
    third = flowing("no_orders", 30, 3)

    Schedule::Reflow.new(@line, blocks: [ engineer, first, second, third ]).call

    assert_equal [
      [ "no_orders", "Mon 06:00", "Mon 07:00" ],
      [ "planned_maintenance", "Mon 08:00", "Mon 10:00" ],
      [ "changeover", "Mon 10:00", "Mon 11:30" ],
      [ "no_orders", "Mon 11:30", "Mon 12:00" ]
    ], timeline(@line)
    assert_equal [ 1, 2, 3, 4 ], @line.schedule_blocks.ordered.map(&:position)
  end

  test "a block that exactly fills the gap before a locked block stays before it" do
    engineer = block("planned_maintenance", 60, line: @line, locked: true, starts_at: at("2026-11-16 08:00"))
    Schedule::Reflow.new(@line, blocks: [ engineer, flowing("no_orders", 120, 1) ]).call
    assert_equal [ "Mon 06:00", "Mon 08:00" ], timeline(@line).first.drop(1)
  end

  test "jumps over several locked blocks in a row" do
    a = block("planned_maintenance", 60, line: @line, locked: true, starts_at: at("2026-11-16 07:00"))
    b = block("planned_maintenance", 60, line: @line, locked: true, starts_at: at("2026-11-16 08:30"))
    Schedule::Reflow.new(@line, blocks: [ b, a, flowing("no_orders", 120, 1) ]).call
    assert_equal [ "no_orders", "Mon 09:30", "Mon 11:30" ], timeline(@line).last
  end

  test "recalculates job durations from the current rate" do
    job = block("job", 30, line: @line, position: 1, sales_order_line: sales_order_lines(:bf_open_700), planned_g: 1_900_000)
    Schedule::Reflow.new(@line, blocks: [ job ]).call
    assert_equal 600, job.reload.duration_minutes

    line_rates(:bf_700_d1).update!(kg_per_hour: 380) # after_commit reflows the line
    assert_equal 300, job.reload.duration_minutes
    assert_equal at("2026-11-16 11:00"), job.ends_at
  end
end
