require "test_helper"

class PlannerControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper

  setup do
    travel_to at("2026-11-16 05:00")
    sign_in_as users(:office)
    @editor = Schedule::Editor.new(lines(:d1))
    @job = @editor.add_job(sales_order_lines(:bf_open_700), planned_g: 1_900_000, starts_at: at(MONDAY_6AM))
  end

  test "floor users are kept out" do
    sign_out
    sign_in_as users(:floor)
    get planner_path
    assert_redirected_to floor_root_path
  end

  test "shows the first line's timeline, queue and orders to plan" do
    get planner_path
    assert_response :success
    assert_select ".tab[aria-current=page]", text: "Line D1"
    assert_select ".timeline-row", 8 # header + 7 days
    assert_select ".timeline-block[style*='grid-column: 13 / 33']" # Mon 06:00–16:00
    assert_select "#schedule_block_#{@job.id}", /SO-00001/
    assert_select "#unplanned_sales_order_line_#{sales_order_lines(:bf_open_700).id}", /8,100 kg to plan/
  end

  test "line and week parameters" do
    get planner_path(line: "d2", week: "2026-11-23")
    assert_select ".tab[aria-current=page]", text: "Line D2"
    assert_select "p", /Week of Mon 23 Nov 2026/
    assert_select ".timeline-block", 0

    get planner_path(week: "nonsense")
    assert_response :success
  end

  test "print view lists each line like form 5.4.1.1" do
    sales_orders(:bf_open).update!(urgent: true)
    get planner_print_path
    assert_response :success
    assert_select "h1", /Line D1/
    assert_select "h1", /Line D2/
    assert_select "tr.print-urgent", /SO-00001/
    assert_select "td", text: ".250"
  end
end
