require "test_helper"

class PlanOptimisationsControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper

  setup do
    travel_to at(MONDAY_6AM)
    @job = planned_job
  end

  teardown { travel_back }

  test "optimise starts a draft, replans it and says what changed, leaving the live plan alone" do
    sign_in_as users(:office)
    get planner_path(line: "D1")
    assert_select "button", "Optimise"

    assert_no_changes -> { ScheduleBlock.live.pluck(:id, :starts_at) } do
      post plan_optimisation_path(line: "D1")
    end
    assert_redirected_to planner_path(line: "D1")
    draft = PlanDraft.current
    assert_equal users(:office), draft.started_by
    assert_match(/Both lines are replanned in the draft\. \d+ orders? late \(was \d+\)/, flash[:notice])
    # The urgent overdue order (not on the plan before) is now planned, ahead of the rest.
    assert draft.blocks.jobs.exists?(sales_order_line: sales_order_lines(:bf_overdue_700))

    follow_redirect!
    assert_select "section[aria-label=Plan]", /Draft plan/
    assert_select "button", "Optimise"
  end

  test "optimise works on the draft already open" do
    sign_in_as users(:office)
    draft = PlanDraft.start!(user: users(:admin))
    post plan_optimisation_path(line: "D1")
    assert_equal [ draft ], PlanDraft.all
  end

  test "floor users can't optimise" do
    sign_in_as users(:floor)
    post plan_optimisation_path
    assert PlanDraft.none?
  end
end
