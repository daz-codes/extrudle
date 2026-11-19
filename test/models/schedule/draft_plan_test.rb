require "test_helper"

class Schedule::DraftPlanTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  setup do
    travel_to at(MONDAY_6AM)
    @d1 = lines(:d1)
    @live = Schedule::Editor.new(@d1)
    @first = @live.add_job(sales_order_lines(:bf_open_700), starts_at: at(MONDAY_6AM))
    @second = @live.add_job(sales_order_lines(:bf_overdue_700))
    @visit = @live.add(block("planned_maintenance", 240, locked: true, starts_at: at("2026-11-25 08:00")))
  end

  def draft_editor(draft, line = @d1) = Schedule::Editor.new(line, plan: draft.plan)

  def draft_copy(draft, live_block) = draft.blocks.find_by!(source_block_id: live_block.id)

  def live_timeline = timeline(@d1)

  def start_log(job, **attributes)
    start = ProductionRun::Start.new(schedule_block: job, **attributes)
    assert start.save, start.errors.full_messages.to_sentence
    start.run
  end

  test "starting a draft copies every live block and queue start, one draft at a time" do
    draft = PlanDraft.start!(user: users(:office))
    assert_equal ScheduleBlock.live.count, draft.blocks.count
    assert_equal @d1.queue_starts_at, draft.queue_start(@d1)
    assert_equal ScheduleBlock.live.pluck(:id).sort, draft.blocks.pluck(:source_block_id).sort
    assert_equal users(:office), draft.started_by
    assert_raises(PlanDraft::AlreadyStarted) { PlanDraft.start! }
  end

  test "editing a draft changes nothing live: plan, floor, order statuses" do
    draft = PlanDraft.start!
    before = live_timeline
    next_job = ProductionRun::Board.next_job_for(@d1)

    editor = draft_editor(draft)
    editor.move(draft_copy(draft, @second), :up)
    editor.add(block("no_orders", 120))
    editor.start_at(at("2026-11-17 06:00"))

    assert_equal before, live_timeline
    assert_equal at(MONDAY_6AM), @d1.reload.queue_starts_at
    assert_equal next_job, ProductionRun::Board.next_job_for(@d1)
    assert_equal at("2026-11-17 06:00"), draft.queue_start(@d1)
    assert_equal sales_order_lines(:bf_overdue_700), draft.plan.blocks_for(@d1).jobs.order(:position).first.sales_order_line
  end

  test "a job planned only in the draft doesn't schedule the order, and counts as planned in the draft" do
    @live.remove(@second)
    order_line = sales_order_lines(:bf_overdue_700)
    draft = PlanDraft.start!
    draft_editor(draft).add_job(order_line)

    assert order_line.sales_order.reload.open?
    assert_equal 0, Schedule::Plan.live.planned_g(order_line)
    assert_equal order_line.quantity_g, draft.plan.planned_g(order_line)
    assert_equal 0, draft.plan.unplanned_g(order_line)
    assert_equal order_line.quantity_g, order_line.unplanned_g
  end

  test "publishing replaces the live plan in one step, keeping locked blocks and production logs" do
    run = start_log(@first)
    draft = PlanDraft.start!
    editor = draft_editor(draft)
    editor.remove(draft_copy(draft, @second))
    added = editor.add(block("no_orders", 120))
    expected = draft.plan.blocks_for(@d1).ordered.map { [ _1.kind, _1.starts_at, _1.ends_at, _1.locked ] }

    Schedule::Publish.new(draft).call

    assert_nil PlanDraft.current
    assert_equal 0, ScheduleBlock.where.not(plan_draft_id: nil).count
    assert_equal expected, @d1.schedule_blocks.ordered.map { [ _1.kind, _1.starts_at, _1.ends_at, _1.locked ] }
    assert_equal @first, run.reload.schedule_block, "the started job was updated in place"
    assert_not ScheduleBlock.exists?(@second.id)
    assert @visit.reload.locked?
    assert @d1.schedule_blocks.exists?(kind: "no_orders")
    assert_not ScheduleBlock.exists?(added.id), "the draft block itself is gone; a live copy took its place"
    assert sales_order_lines(:bf_overdue_700).sales_order.reload.open?, "its job came off, so it's open again"
  end

  test "an unchanged draft publishes to the same plan" do
    before = live_timeline
    draft = PlanDraft.start!
    assert Schedule::Publish.new(draft).changes.none?(&:any?)
    Schedule::Publish.new(draft).call
    assert_equal before, live_timeline
  end

  test "a started job can't be moved or removed in the draft, even if it started after the draft began" do
    draft = PlanDraft.start!
    start_log(@first)
    copy = draft_copy(draft, @first)
    assert_raises(Schedule::Error) { draft_editor(draft).remove(copy) }
    assert_raises(Schedule::Error) { draft_editor(draft).move(copy, :down) }
    assert_equal @first.production_run, copy.started_run
  end

  test "a job the draft took off but that started meanwhile stays on the plan, first, and the review says so" do
    draft = PlanDraft.start!
    draft_editor(draft).remove(draft_copy(draft, @first))
    run = start_log(@first, despatch_number: 731)

    publish = Schedule::Publish.new(draft)
    assert_match "Despatch 731", publish.notes.join
    assert_match "stays on the plan, first in the queue", publish.notes.join
    publish.call

    assert_equal @first, @d1.schedule_blocks.ordered.detect(&:job?)
    assert_equal @first, run.reload.schedule_block
  end

  test "cancelling an order while drafting takes its jobs off both plans" do
    draft = PlanDraft.start!
    order = @second.sales_order
    order.cancel!
    assert_not draft.plan.blocks.jobs.where(sales_order_line: @second.sales_order_line).exists?
    assert_not ScheduleBlock.exists?(@second.id)
    assert_match "#{order.number} was cancelled after the draft began", Schedule::Publish.new(draft).notes.join
  end

  test "an order added after the draft began is listed before publishing" do
    draft = PlanDraft.start!
    travel 1.minute
    order_line = stock_order_line
    assert_match "#{order_line.sales_order.number} #{order_line.product_spec} was added after the draft began",
                 Schedule::Publish.new(draft).notes.join
  end

  test "discarding leaves the live plan as it was" do
    before = live_timeline
    draft = PlanDraft.start!
    draft_editor(draft).remove(draft_copy(draft, @second))
    draft.discard!
    assert_nil PlanDraft.current
    assert_equal before, live_timeline
  end

  test "a new line rate re-times the draft as well as the live plan" do
    draft = PlanDraft.start!
    line_rates(:bf_700_d1).update!(kg_per_hour: 95)
    assert_equal @first.reload.duration_minutes, draft_copy(draft, @first).duration_minutes
    assert_operator @first.duration_minutes, :>, 3_180
  end
end
