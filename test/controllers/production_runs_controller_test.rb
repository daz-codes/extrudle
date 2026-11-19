require "test_helper"

class ProductionRunsControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper

  setup do
    @job = planned_job
    sign_in_as users(:floor)
  end

  def start_run(**params)
    post production_runs_path, params: { production_run_start: { schedule_block_id: @job.id, despatch_number: "731",
      started_at: Time.current.strftime("%Y-%m-%dT%H:%M"), technician_days: "Dave", antiblock_batch_no: "AB-1" }.merge(params) }
    ProductionRun.last
  end

  test "floor users see the lines on the floor page and use the floor layout" do
    get floor_root_path
    assert_select "#production_line_#{lines(:d1).id}", /Next on the plan/
    assert_select "a", text: "Start log"

    get new_production_run_path(block: @job.id)
    assert_response :success
    assert_select "nav[aria-label=Main]", count: 0
  end

  test "office users get the office layout" do
    sign_out
    sign_in_as users(:office)
    get production_runs_path
    assert_select "nav[aria-label=Main]"
    assert_select "a", text: "Start log"
  end

  test "start a log from the next job" do
    run = start_run
    assert_redirected_to production_run_path(run)
    assert_equal [ 731, "Dave", "AB-1", users(:floor) ], [ run.despatch_number, run.technician_days, run.antiblock_batch_no, run.started_by ]

    follow_redirect!
    assert_select "h1", /Despatch\s+731/
    assert_select "dd", text: "BF-700-250"
    assert_select "dd", text: ".250"

    get floor_root_path
    assert_select "#production_line_#{lines(:d1).id}", /Despatch 731/
  end

  test "a bad start re-renders with errors" do
    start_run
    ProductionRun.last.update_columns(status: "finished")
    @job = planned_job(stock_order_line)
    post production_runs_path, params: { production_run_start: { schedule_block_id: @job.id, despatch_number: "731", started_at: Time.current.strftime("%Y-%m-%dT%H:%M") } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Despatch number has already been taken/
  end

  test "prestart answers and measurements" do
    run = start_run
    post production_run_checks_path(run), params: { stage: "prestart", item: "previous_documents_removed", passed: "true" }
    assert_redirected_to production_run_path(run, anchor: "prestart")
    assert_equal "Previous documents and labels removed: yes.", flash[:notice]

    post production_run_checks_path(run), params: { stage: "startup", item: "thickness", actual: ".265" }
    assert_equal "Thickness 265 µm: out of tolerance.", flash[:alert]

    post production_run_checks_path(run), params: { stage: "startup", item: "width", actual: "wide" }
    assert_match "wasn't saved", flash[:alert]

    get production_run_path(run)
    assert_select "#check_prestart_previous_documents_removed", /Pass/
    assert_select "#measure_startup_thickness .bg-bad-50", /265 µm \(\+15\)/
  end

  test "edit the log's details while it runs, not after" do
    run = start_run
    patch production_run_path(run), params: { production_run: { silicone_batch_no: "SE-9", comments: "Gauge drift at 02:00, adjusted die" } }
    assert_redirected_to production_run_path(run)
    assert_equal "SE-9", run.reload.silicone_batch_no

    run.update_columns(status: "finished")
    get edit_production_run_path(run)
    assert_redirected_to production_run_path(run)
    post production_run_checks_path(run), params: { stage: "prestart", item: "previous_product_cleared", passed: "true" }
    assert_match "is finished", flash[:alert]
  end

  test "a comment added from the end-of-run tab goes back there" do
    run = start_run
    get edit_production_run_path(run, return_to: "finish")
    assert_select "input[type=hidden][name=return_to][value=finish]"
    assert_select "a[href='#{production_run_finish_path(run)}']", "Cancel"

    patch production_run_path(run), params: { return_to: "finish", production_run: { comments: "Thick edge, die adjusted" } }
    assert_redirected_to production_run_finish_path(run)
  end

  test "the log downloads as a PDF for the floor and the office" do
    run = start_run
    [ users(:floor), users(:office) ].each do |user|
      sign_in_as user
      get production_run_path(run)
      assert_select "a[href='#{production_run_path(run, format: :pdf)}']", "Print log"

      get production_run_path(run, format: :pdf)
      assert_response :success
      assert_equal "application/pdf", response.media_type
      assert_match "despatch-#{run.despatch_number}-in-progress.pdf", response.headers["Content-Disposition"]
      assert response.body.start_with?("%PDF")
    end
  end
end
