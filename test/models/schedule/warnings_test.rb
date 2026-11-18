require "test_helper"

class Schedule::WarningsTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  setup do
    travel_to at(MONDAY_6AM)
    @d1 = lines(:d1)
    @editor = Schedule::Editor.new(@d1)
  end

  def codes(block)
    Schedule::Warnings.for_line(@d1)[block.reload].map(&:code)
  end

  test "no warnings for a job that fits" do
    order_line = sales_order_lines(:bf_open_700)
    order_line.sales_order.update!(required_on: Date.new(2026, 11, 30))
    assert_empty codes(@editor.add_job(order_line))
  end

  test "late when the job finishes after the end of the required day (UK time)" do
    order_line = sales_order_lines(:bf_open_700)
    order_line.sales_order.update!(required_on: Date.new(2026, 11, 18))
    job = @editor.add_job(order_line, planned_g: 7_980_000) # 42 h: Mon 06:00 → Wed 00:00
    assert_not_includes codes(job), :late

    @editor.replan(job, 9_500_000) # 50 h → Wed 08:00, still Wednesday
    assert_not_includes codes(job), :late

    @editor.replan(job, 10_000_000) # 53 h → Wed 11:00 is fine... move required date back a day
    order_line.sales_order.update!(required_on: Date.new(2026, 11, 17))
    warning = Schedule::Warnings.for_line(@d1)[job.reload].detect { _1.code == :late }
    assert_match(/after SO-00001's required date \(Tue 17 Nov\)/, warning.message)
  end

  test "no rate for the line" do
    job = @editor.add_job(stock_order_line, duration_minutes: 120)
    warning = Schedule::Warnings.for_line(@d1)[job.reload].first
    assert_equal :no_rate, warning.code
    assert_match(/no rate for STK-1000-500, so 2h is an estimate/, warning.message)
  end

  test "over planned when more is planned than ordered" do
    order_line = sales_order_lines(:bf_open_700)
    job = @editor.add_job(order_line, planned_g: 12_000_000)
    warning = Schedule::Warnings.for_line(@d1)[job.reload].detect { _1.code == :over_planned }
    assert_match(/12000 kg planned .* but 10000 kg is ordered/, warning.message)
  end

  test "idle time before a locked block" do
    @editor.add(block("planned_maintenance", 60, locked: true, starts_at: at("2026-11-16 08:00")))
    @editor.add(block("no_orders", 90, position: nil))
    @editor.add(block("changeover", 60))

    visit = @d1.schedule_blocks.planned_maintenance.first
    warning = Schedule::Warnings.for_line(@d1)[visit].first
    assert_equal :idle, warning.code
    assert_match(/idle for 30m before this planned maintenance/, warning.message)
  end
end
