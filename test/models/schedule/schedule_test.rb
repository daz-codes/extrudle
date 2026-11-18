require "test_helper"

class ScheduleTest < ActiveSupport::TestCase
  test "rounds minutes up to whole 30-minute slots" do
    assert_equal 30, Schedule.round_up_to_slot(1)
    assert_equal 30, Schedule.round_up_to_slot(30)
    assert_equal 60, Schedule.round_up_to_slot(31)
  end

  test "snaps times up to the next slot boundary" do
    assert_equal Time.zone.parse("2026-11-16 06:00"), Schedule.snap_up(Time.zone.parse("2026-11-16 06:00"))
    assert_equal Time.zone.parse("2026-11-16 06:30"), Schedule.snap_up(Time.zone.parse("2026-11-16 06:00:01"))
    assert Schedule.on_slot?(Time.zone.parse("2026-07-01 14:30")), "BST slots line up with UTC"
  end

  test "job minutes come from planned weight over the line rate, rounded up" do
    assert_equal 3_180, Schedule.job_minutes(10_000_000, 190) # 52.6 h, like paper log 731
    assert_equal 60, Schedule.job_minutes(190_000, 190)        # exactly an hour
    assert_equal 90, Schedule.job_minutes(190_001, 190)        # one gram over
    assert_equal 30, Schedule.job_minutes(1, 190)              # never less than a slot
  end
end
