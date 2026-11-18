require "test_helper"

class Schedule::TimelineTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  def placed(kind, from, to)
    ScheduleBlock.new(kind: kind, starts_at: at(from), ends_at: at(to), duration_minutes: ((at(to) - at(from)) / 60).to_i)
  end

  test "a week of days with 48 slots each" do
    timeline = Schedule::Timeline.new([], week_start: Date.new(2026, 11, 16))
    assert_equal (Date.new(2026, 11, 16)..Date.new(2026, 11, 22)).to_a, timeline.days.map(&:date)
    assert_equal [ 48 ], timeline.days.map(&:slots).uniq
  end

  test "places a block in slot columns" do
    day = Schedule::Timeline.new([ placed("no_orders", "2026-11-16 06:00", "2026-11-16 07:00") ], week_start: Date.new(2026, 11, 16)).days.first
    segment = day.segments.sole
    assert_equal [ 13, 15, 2 ], [ segment.from_slot, segment.to_slot, segment.span ]
    assert_not segment.continues_before
    assert_not segment.continues_after
  end

  test "a block across midnight shows on both days" do
    days = Schedule::Timeline.new([ placed("job", "2026-11-16 22:00", "2026-11-17 03:00") ], week_start: Date.new(2026, 11, 16)).days
    monday, tuesday = days.first(2).map { _1.segments.sole }
    assert_equal [ 45, 49 ], [ monday.from_slot, monday.to_slot ]
    assert monday.continues_after
    assert_equal [ 1, 7 ], [ tuesday.from_slot, tuesday.to_slot ]
    assert tuesday.continues_before
  end

  test "clock-change days have 46 and 50 slots (UK time)" do
    spring = Schedule::Timeline.new([], week_start: Date.new(2026, 3, 23)).days.last
    autumn = Schedule::Timeline.new([], week_start: Date.new(2026, 10, 19)).days.last
    assert_equal [ Date.new(2026, 3, 29), 46 ], [ spring.date, spring.slots ]
    assert_equal [ Date.new(2026, 10, 25), 50 ], [ autumn.date, autumn.slots ]
  end

  test "hour labels and the now marker" do
    travel_to at("2026-11-16 12:00")
    day = Schedule::Timeline.new([], week_start: Date.new(2026, 11, 16)).days.first
    assert_equal 24, day.hours.size
    assert_equal [ 13, at("2026-11-16 06:00") ], day.hours[6]
    assert_equal 50.0, day.now_percent
    assert_nil Schedule::Timeline.new([], week_start: Date.new(2026, 11, 16)).days.second.now_percent
  end

  test "week start is the Monday" do
    assert_equal Date.new(2026, 11, 16), Schedule::Timeline.week_start_for(Date.new(2026, 11, 22))
  end
end
