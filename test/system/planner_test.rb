require "application_system_test_case"

class PlannerTest < ApplicationSystemTestCase
  include ScheduleTestHelper

  setup do
    travel_to at("2026-11-16 05:00")
    sign_in users(:office)
  end

  teardown { travel_back }

  test "plan two orders, see the changeover, reorder and remove" do
    click_on "Planner"
    assert_selector ".tab[aria-current=page]", text: "Line D1"
    assert_text "Nothing planned on line D1 yet"

    within "#unplanned_sales_order_line_#{sales_order_lines(:bf_open_700).id}" do
      fill_in "Planned kg", with: "1900"
      click_on "Add to D1"
    end
    assert_text "Added SO-00001 BF-700-250 to line D1"
    assert_selector ".timeline-block", text: "SO-00001"

    within "#unplanned_sales_order_line_#{sales_order_lines(:bf_overdue_700).id}" do
      click_on "Add to D1"
    end
    assert_text "Added SO-00002 BF-700-250 to line D1"

    choose "No orders"
    fill_in "Hours", with: "2"
    select "Before 1. SO-00001 · BF-700-250", from: "Where"
    click_on "Add to line D1"
    assert_text "Added No orders to line D1"

    assert_selector "#planner_board tbody tr:first-child", text: "No orders"

    click_on "Move No orders later"
    assert_selector "#planner_board tbody tr:first-child", text: "SO-00001"
    assert_selector "#planner_board tbody tr:nth-child(2)", text: "No orders"

    accept_confirm { click_on "Remove No orders" }
    assert_text "Removed No orders from line D1"
    assert_no_selector "#planner_board tbody tr", text: "No orders"
  end
end
