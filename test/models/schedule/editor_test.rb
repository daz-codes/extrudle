require "test_helper"

class Schedule::EditorTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  setup do
    travel_to at(MONDAY_6AM)
    @d1 = lines(:d1)
    @editor = Schedule::Editor.new(@d1)
    @order_line = sales_order_lines(:bf_open_700) # 10 t of BF-700-250, the only line on SO-00001
  end

  test "add_job plans what's left of the order line and times it from the rate" do
    job = @editor.add_job(@order_line)
    assert_equal 10_000_000, job.planned_g
    assert_equal 3_180, job.duration_minutes
    assert_equal [ at(MONDAY_6AM), at("2026-11-18 11:00") ], [ job.starts_at, job.ends_at ]
  end

  test "the order becomes scheduled when every line is fully planned, and open again when not" do
    order = @order_line.sales_order
    job = @editor.add_job(@order_line, planned_g: 6_000_000)
    assert order.reload.open?, "only 6 of 10 t planned"

    Schedule::Editor.new(lines(:d2)).add_job(@order_line) # the other 4 t on D2
    assert order.reload.scheduled?
    assert_equal 4_000_000, lines(:d2).schedule_blocks.first.planned_g

    @editor.remove(job)
    assert order.reload.open?
  end

  test "can't plan a fully planned line or a finished order" do
    @editor.add_job(@order_line)
    error = assert_raises(Schedule::Error) { @editor.add_job(@order_line) }
    assert_match(/already fully planned/, error.message)

    error = assert_raises(Schedule::Error) { @editor.add_job(sales_order_lines(:bf_dispatched_700)) }
    assert_match(/dispatched/, error.message)
  end

  test "adds a changeover between jobs for different specs, using the line default" do
    @editor.add_job(@order_line, planned_g: 190_000)
    @editor.add_job(stock_order_line)

    assert_equal %w[job changeover job], @d1.schedule_blocks.ordered.map(&:kind)
    changeover = @d1.schedule_blocks.changeover.first
    assert_equal 60, changeover.duration_minutes
    assert_equal [ at("2026-11-16 07:00"), at("2026-11-16 08:00") ], [ changeover.starts_at, changeover.ends_at ]
  end

  test "no changeover between jobs for the same spec" do
    @editor.add_job(@order_line, planned_g: 190_000)
    @editor.add_job(sales_order_lines(:bf_overdue_700))
    assert_equal %w[job job], @d1.schedule_blocks.ordered.map(&:kind)
  end

  test "inserting a different spec between two jobs adds changeovers on both sides" do
    @editor.add_job(@order_line, planned_g: 190_000)
    @editor.add_job(sales_order_lines(:bf_overdue_700))
    @editor.add_job(stock_order_line, position: 2)

    assert_equal %w[job changeover job changeover job], @d1.schedule_blocks.ordered.map(&:kind)
  end

  test "changeover rounds the line default up to a slot, and is skipped when the default is 0" do
    @d1.update!(default_changeover_minutes: 45)
    @editor.add_job(@order_line, planned_g: 190_000)
    @editor.add_job(stock_order_line)
    assert_equal 60, @d1.schedule_blocks.changeover.first.duration_minutes

    lines(:d2).update!(default_changeover_minutes: 0)
    d2 = Schedule::Editor.new(lines(:d2))
    d2.add_job(sales_order_lines(:bf_overdue_700))
    d2.add_job(stock_order_line)
    assert_equal %w[job job], lines(:d2).schedule_blocks.ordered.map(&:kind)
  end

  test "add at a position inserts before the block there and later blocks shift" do
    first = @editor.add(block("no_orders", 60))
    second = @editor.add(block("no_orders", 30))
    inserted = @editor.add(block("changeover", 90), position: 1)

    assert_equal [ inserted, first, second ].map(&:id), @d1.schedule_blocks.ordered.map(&:id)
    assert_equal [ [ "changeover", "Mon 06:00", "Mon 07:30" ], [ "no_orders", "Mon 07:30", "Mon 08:30" ], [ "no_orders", "Mon 08:30", "Mon 09:00" ] ], timeline(@d1)
  end

  test "move up and down swap with the neighbour and re-time" do
    a = @editor.add(block("no_orders", 60))
    b = @editor.add(block("changeover", 30))
    c = @editor.add(block("no_orders", 90))

    @editor.move(c, :up)
    assert_equal [ a, c, b ].map(&:id), @d1.schedule_blocks.ordered.map(&:id)
    @editor.move(a, :down)
    assert_equal [ c, a, b ].map(&:id), @d1.schedule_blocks.ordered.map(&:id)
    assert_equal [ [ "no_orders", "Mon 06:00", "Mon 07:30" ], [ "no_orders", "Mon 07:30", "Mon 08:30" ], [ "changeover", "Mon 08:30", "Mon 09:00" ] ], timeline(@d1)

    @editor.move(c, :up) # already first: no change
    @editor.move(b, :down) # already last: no change
    assert_equal [ c, a, b ].map(&:id), @d1.schedule_blocks.ordered.map(&:id)
  end

  test "move_to puts a block at a position" do
    a = @editor.add(block("no_orders", 30))
    b = @editor.add(block("no_orders", 30))
    c = @editor.add(block("no_orders", 30))
    @editor.move_to(c, 1)
    assert_equal [ c, a, b ].map(&:id), @d1.schedule_blocks.ordered.map(&:id)
  end

  test "the line keeps its start when the first block is removed or moved down" do
    a = @editor.add(block("no_orders", 60))
    @editor.add(block("changeover", 30))
    travel_to at("2026-11-16 09:00")

    @editor.remove(a)
    assert_equal [ [ "changeover", "Mon 06:00", "Mon 06:30" ] ], timeline(@d1)
  end

  test "resize non-job blocks; jobs with a rate are sized by weight" do
    gap = @editor.add(block("no_orders", 60))
    @editor.resize(gap, 120)
    assert_equal 120, gap.reload.duration_minutes

    job = @editor.add_job(@order_line)
    assert_raises(Schedule::Error) { @editor.resize(job, 60) }

    @editor.replan(job, 1_900_000)
    assert_equal 600, job.reload.duration_minutes
  end

  test "jobs with no rate keep a manual duration that can be resized" do
    job = @editor.add_job(stock_order_line, duration_minutes: 240)
    assert_equal 240, job.duration_minutes
    @editor.resize(job, 300)
    assert_equal 300, job.reload.duration_minutes
  end

  test "invalid durations are reported as schedule errors" do
    gap = @editor.add(block("no_orders", 60))
    error = assert_raises(Schedule::Error) { @editor.resize(gap, 45) }
    assert_match(/multiple of 30/, error.message)
  end

  test "lock pins a block at a time; unlock returns it to the queue" do
    a = @editor.add(block("no_orders", 60))
    visit = @editor.add(block("planned_maintenance", 120))
    @editor.lock(visit, starts_at: at("2026-11-17 13:50"))
    assert_equal [ at("2026-11-17 14:00"), at("2026-11-17 16:00") ], [ visit.reload.starts_at, visit.ends_at ]

    @editor.move(a, :down)
    assert_equal at("2026-11-17 14:00"), visit.reload.starts_at, "locked blocks don't move"

    @editor.unlock(visit)
    assert_equal [ [ "no_orders", "Mon 06:00", "Mon 07:00" ], [ "planned_maintenance", "Mon 07:00", "Mon 09:00" ] ], timeline(@d1)
  end

  test "locked blocks can't be moved, need a start, and can't overlap" do
    visit = @editor.add(block("planned_maintenance", 120, locked: true, starts_at: at("2026-11-16 14:00")))
    assert_raises(Schedule::Error) { @editor.move(visit, :up) }
    assert_raises(Schedule::Error) { @editor.add(block("planned_maintenance", 60, locked: true)) }

    error = assert_raises(Schedule::Error) { @editor.add(block("unplanned_maintenance", 60, locked: true, starts_at: at("2026-11-16 15:00"))) }
    assert_match(/overlaps the locked/, error.message)
  end

  test "the first block on an empty line can set when the queue starts" do
    @editor.add(block("planned_maintenance", 60, locked: true, starts_at: at("2026-11-16 20:00")))
    job = @editor.add_job(sales_order_lines(:bf_open_700), planned_g: 190_000, starts_at: at("2026-11-16 07:45"))
    assert_equal at("2026-11-16 08:00"), job.starts_at

    later = @editor.add(block("no_orders", 60))
    assert_equal at("2026-11-16 09:00"), later.starts_at, "later blocks keep the queue's start"
  end

  test "start_at moves the whole queue" do
    @editor.add(block("no_orders", 60))
    @editor.start_at(at("2026-11-23 06:00"))
    assert_equal [ [ "no_orders", "Mon 06:00", "Mon 07:00" ] ], timeline(@d1)
    assert_equal at("2026-11-23 06:00"), @d1.schedule_blocks.first.starts_at
  end

  test "cancelling an order takes its jobs off every line and closes the gap" do
    order = @order_line.sales_order
    @editor.add_job(@order_line, planned_g: 190_000)
    after = @editor.add(block("no_orders", 60))
    Schedule::Editor.new(lines(:d2)).add_job(@order_line)

    order.cancel!
    assert order.reload.cancelled?
    assert_empty ScheduleBlock.jobs.where(sales_order_line: @order_line)
    assert_equal at(MONDAY_6AM), after.reload.starts_at
  end

  test "an order line on the planner can't be deleted" do
    @editor.add_job(@order_line)
    assert_not @order_line.destroy
  end

  test "changing an order line's quantity updates the order's scheduled status" do
    order = @order_line.sales_order
    @editor.add_job(@order_line)
    assert order.reload.scheduled?

    @order_line.update!(quantity: "12000")
    assert order.reload.open?, "2 t more now needs planning"
  end
end
