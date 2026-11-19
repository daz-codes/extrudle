require "test_helper"

class PlanDraftsControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper

  setup do
    @job = planned_job
    sign_in_as users(:office)
  end

  test "the planner offers a new plan, then shows the draft with its actions" do
    get planner_path
    assert_select "button", "Start a new plan"

    post plan_draft_path(line: "D1")
    assert_redirected_to planner_path(line: "D1")
    draft = PlanDraft.current
    assert_equal users(:office), draft.started_by

    follow_redirect!
    assert_select "section[aria-label=Plan]", /Draft plan/
    assert_select "a", "Review and publish"
    assert_select "a", "View live plan"
    assert_select "#schedule_block_#{draft.blocks.sole.id}"
  end

  test "starting a second draft is refused" do
    PlanDraft.start!
    post plan_draft_path
    assert_match "already being drafted", flash[:alert]
    assert_equal 1, PlanDraft.count
  end

  test "while drafting, the live plan is read only and edits go to the draft" do
    draft = PlanDraft.start!
    copy = draft.blocks.sole

    get planner_path(plan: "live")
    assert_select "section[aria-label=Plan]", /Read only/
    assert_select "#schedule_block_#{@job.id}"
    assert_select "#add-job-heading", count: 0
    assert_select "button[aria-label^=Remove]", count: 0

    delete schedule_block_path(@job)
    assert_match "A new plan is being drafted", flash[:alert]
    assert ScheduleBlock.exists?(@job.id)

    post schedule_blocks_path, params: { line_id: lines(:d1).id, kind: "no_orders", duration_hours: "2" }
    assert_equal 2, draft.blocks.count
    assert_equal 1, lines(:d1).schedule_blocks.count

    patch schedule_block_path(copy), params: { notes: "Draft only" }
    assert_equal "Draft only", copy.reload.notes
    assert_nil @job.reload.notes
  end

  test "review, then publish" do
    draft = PlanDraft.start!
    Schedule::Editor.new(lines(:d1), plan: draft.plan).add(block("no_orders", 120))

    get plan_draft_path
    assert_select "#changes_line_#{lines(:d1).id} td", "1"
    assert_select "button", "Publish the new plan"

    post publish_plan_draft_path
    assert_redirected_to planner_path
    assert_equal "The new plan is live.", flash[:notice]
    assert_nil PlanDraft.current
    assert lines(:d1).schedule_blocks.exists?(kind: "no_orders")
  end

  test "discard" do
    PlanDraft.start!
    delete plan_draft_path
    assert_nil PlanDraft.current
    assert ScheduleBlock.exists?(@job.id)
  end

  test "publishing or discarding a draft someone else got to first" do
    draft = PlanDraft.start!
    gone = PlanDraft.find(draft.id)
    draft.discard!
    original = PlanDraft.method(:current)
    PlanDraft.define_singleton_method(:current) { gone } # loaded just before the other person's click

    post publish_plan_draft_path
    assert_redirected_to planner_path
    assert_match "already published or discarded", flash[:alert]

    delete plan_draft_path
    assert_match "already published or discarded", flash[:alert]
  ensure
    PlanDraft.define_singleton_method(:current, original) if original
  end

  test "the draft prints, marked as a draft" do
    PlanDraft.start!
    get planner_print_path
    assert_match "DRAFT, not yet live", response.body
    get planner_print_path(plan: "live")
    assert_no_match "DRAFT", response.body
  end

  test "the floor only ever sees the live plan" do
    draft = PlanDraft.start!
    Schedule::Editor.new(lines(:d1), plan: draft.plan).remove(draft.blocks.sole)
    sign_in_as users(:floor)
    get floor_root_path
    assert_select "#production_line_#{lines(:d1).id}", /Next on the plan/

    post plan_draft_path
    assert_redirected_to floor_root_path
  end
end
