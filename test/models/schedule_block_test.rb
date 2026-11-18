require "test_helper"

class ScheduleBlockTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  def valid_block(**attrs)
    ScheduleBlock.new({ line: lines(:d1), kind: "no_orders", position: 1, duration_minutes: 60,
                        starts_at: at(MONDAY_6AM), ends_at: at(MONDAY_6AM) + 1.hour }.merge(attrs))
  end

  test "valid non-job block" do
    assert valid_block.valid?
  end

  test "durations are whole slots" do
    assert_not valid_block(duration_minutes: 45, ends_at: at(MONDAY_6AM) + 45.minutes).valid?
  end

  test "times sit on slot boundaries and match the duration" do
    assert_not valid_block(starts_at: at("2026-11-16 06:10"), ends_at: at("2026-11-16 07:10")).valid?
    assert_not valid_block(ends_at: at(MONDAY_6AM) + 2.hours).valid?
  end

  test "jobs need an order line and weight; other blocks mustn't have them" do
    job = valid_block(kind: "job")
    assert_not job.valid?
    assert job.errors.include?(:sales_order_line)
    assert job.errors.include?(:planned_kg), "errors show on the kg form field"

    assert_not valid_block(planned_g: 1_000).valid?
  end

  test "planned weight in kg" do
    block = valid_block(kind: "job", sales_order_line: sales_order_lines(:bf_open_700), planned_kg: "2,500.5")
    assert_equal 2_500_500, block.planned_g
  end

  test "job duration comes from the line rate" do
    job = valid_block(kind: "job", sales_order_line: sales_order_lines(:bf_open_700), planned_g: 1_900_000)
    assert_equal 600, job.calculated_duration_minutes # 1,900 kg at 190 kg/h on D1

    job.line = lines(:d2)
    assert_equal 660, job.calculated_duration_minutes # 175 kg/h on D2 → 10.9 h → 11 h
  end

  test "locked blocks can't overlap each other" do
    valid_block(locked: true).save!
    clash = valid_block(locked: true, starts_at: at(MONDAY_6AM) + 30.minutes, ends_at: at(MONDAY_6AM) + 90.minutes)
    assert_not clash.valid?
    assert_match(/overlaps the locked/, clash.errors[:starts_at].first)

    assert valid_block(locked: true, line: lines(:d2)).valid?, "other lines don't clash"
  end
end
