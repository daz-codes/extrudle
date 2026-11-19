require "application_system_test_case"

class DraftPlansTest < ApplicationSystemTestCase
  include ScheduleTestHelper

  setup do
    travel_to at("2026-11-16 05:00")
    @first = planned_job(sales_order_lines(:bf_open_700), starts_at: at("2026-11-16 06:00"))
    @second = planned_job(sales_order_lines(:bf_overdue_700))
    sign_in users(:office)
  end

  teardown { travel_back }

  test "prepare a new plan as a draft, check the live plan is untouched, then publish it" do
    click_on "Planner"
    click_on "Start a new plan"
    assert_text "New plan started from the live plan"
    assert_text "Draft plan"

    # SO-00002 moves to the front of the draft.
    draft_second = PlanDraft.current.blocks.find_by!(source_block_id: @second.id)
    within("#schedule_block_#{draft_second.id}") { click_on "▲" }
    assert_selector "tbody tr:first-child", text: "SO-00002"

    click_on "View live plan"
    assert_text "Read only"
    assert_selector "tbody tr:first-child", text: "SO-00001"
    assert_no_text "Orders to plan"

    click_on "Back to the draft"
    click_on "Review and publish"
    within("#changes_line_#{lines(:d1).id}") { assert_selector "td", text: "Line D1" }
    accept_confirm { click_on "Publish the new plan" }

    assert_text "The new plan is live."
    assert_text "Start a new plan"
    assert_selector "tbody tr:first-child", text: "SO-00002"
    assert_operator @second.reload.starts_at, :<, @first.reload.starts_at
  end
end
