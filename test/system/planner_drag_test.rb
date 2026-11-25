require "application_system_test_case"

# Drag and drop on the planner (Slice 10).
class PlannerDragTest < ApplicationSystemTestCase
  include ScheduleTestHelper

  setup do
    travel_to at("2026-11-16 05:00")
    editor = Schedule::Editor.new(lines(:d1))
    @a = editor.add(block("no_orders", 120, notes: "First"), starts_at: at(MONDAY_6AM)) # 06:00–08:00
    @b = editor.add(block("changeover", 120))                                              # 08:00–10:00
    @c = editor.add(block("no_orders", 120, notes: "Third"))                               # 10:00–12:00
    sign_in users(:office)
  end

  teardown { travel_back }

  def bar(block_record)
    find(".timeline-block[href*='/planner/blocks/#{block_record.id}/edit']")
  end

  # One Selenium action builder per test, so a held button stays held between steps.
  def pointer
    @pointer ||= page.driver.browser.action
  end

  def queue_order
    lines(:d1).schedule_blocks.reload.ordered.map(&:id)
  end

  test "drag a bar onto the start of an earlier one and it goes in first" do
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    # Over the left half of the first bar (06:00–08:00): before it.
    first = bar(@a).native
    pointer.click_and_hold(bar(@c).native).move_by(-20, 0).perform
    pointer.move_to(first, -first.size.width / 4, 0).perform
    assert_selector ".timeline-insert", text: "First, before No orders"
    pointer.release.perform

    assert_text "No orders now runs Mon 16 Nov 06:00 – 08:00"
    assert_equal [ @c, @a, @b ].map(&:id), queue_order
    assert_selector "#planner_board tbody tr:first-child", text: "Third"
  end

  test "drag maintenance between two blocks and the rest move along" do
    maintenance = Schedule::Editor.new(lines(:d1)).add(block("planned_maintenance", 60)) # 12:00–13:00
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    # Over the right half of the first bar: between it and the changeover.
    first = bar(@a).native
    pointer.click_and_hold(bar(maintenance).native).move_by(-20, 0).perform
    pointer.move_to(first, first.size.width / 4, 0).perform
    assert_selector ".timeline-insert", text: "Between No orders and Changeover · Mon 16 Nov, 08:00"
    pointer.release.perform

    assert_text "Planned maintenance now runs Mon 16 Nov 08:00 – 09:00."
    assert_equal [ @a, maintenance, @b, @c ].map(&:id), queue_order
    assert_not maintenance.reload.locked?
    assert_equal at("2026-11-16 09:00"), @b.reload.starts_at
  end

  test "the line says when a drop would pass a job that has started, and nothing is sent" do
    job = Schedule::Editor.new(lines(:d1)).add_job(sales_order_lines(:bf_open_700), planned_g: 380_000) # 12:00–14:00
    maintenance = Schedule::Editor.new(lines(:d1)).add(block("planned_maintenance", 60))                 # 14:00–15:00
    assert ProductionRun::Start.new(schedule_block: job).tap { _1.user = users(:floor) }.save
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    first = bar(@a).native
    pointer.click_and_hold(bar(maintenance).native).move_by(-20, 0).perform
    pointer.move_to(first, -first.size.width / 4, 0).perform
    assert_selector ".timeline-insert.is-blocked", text: "Can't go here: SO-00001 BF-700-250 has started"
    pointer.release.perform
    wait_for_turbo

    assert_no_text "now runs"
    assert_equal [ @a, @b, @c, job, maintenance ].map(&:id), queue_order
  end

  test "dropping a bar back where it is changes nothing" do
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    pointer.click_and_hold(bar(@b).native).move_by(-20, 0).perform
    assert_selector ".timeline-insert", text: "Stays here"
    pointer.release.perform
    wait_for_turbo
    assert_no_text "now runs"
    assert_equal [ @a, @b, @c ].map(&:id), queue_order
  end

  test "drag a queue row by its handle" do
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    find("#schedule_block_#{@b.id} .queue-handle").drag_to(find("#schedule_block_#{@a.id}"))
    assert_text "Changeover now runs Mon 16 Nov 06:00 – 08:00"
    assert_equal [ @b, @a, @c ].map(&:id), queue_order
  end

  test "a locked row isn't a place in the queue, so a row can't be dropped on it" do
    maintenance = Schedule::Editor.new(lines(:d1)).add(block("planned_maintenance", 60, locked: true, starts_at: at("2026-11-16 14:00")))
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    pointer.click_and_hold(find("#schedule_block_#{@a.id} .queue-handle").native).move_by(0, 20).perform
    pointer.move_to(find("#schedule_block_#{maintenance.id}").native).perform
    assert_no_selector "tr.drop-before, tr.drop-after"
    pointer.release.perform

    wait_for_turbo
    assert_no_text "now runs"
    assert_equal [ @a, @b, @c, maintenance ].map(&:id), queue_order
  end

  test "resting near the side of a narrow timeline scrolls it" do
    page.driver.browser.manage.window.resize_to(800, 1000)
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo
    scroller = find("[data-planner-drag-target=scroller]")
    assert_equal 0, scroller.evaluate_script("this.scrollLeft")

    pointer.click_and_hold(bar(@a).native).move_by(10, 0).perform
    pointer.move_to(scroller.native, scroller.native.size.width / 2 - 10, 0).perform # just inside its right-hand side
    assert eventually { scroller.evaluate_script("this.scrollLeft").positive? }, "the timeline scrolls sideways"
    pointer.send_keys(:escape).release.perform
  ensure
    page.driver.browser.manage.window.resize_to(1400, 1000)
  end

  # Waits up to 2 real seconds (travel_to freezes Time) for the block to be true.
  def eventually
    give_up = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 2
    until (result = yield) || Process.clock_gettime(Process::CLOCK_MONOTONIC) > give_up
      sleep 0.05
    end
    result
  end

  test "letting go beside the timeline cancels the drag" do
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    pointer.click_and_hold(bar(@c).native).move_by(-40, 0).perform
    assert_selector ".timeline-insert"
    # Level with Monday's track, but just past its right-hand end.
    monday = find(".timeline-track[data-day-start^='2026-11-16']")
    pointer.move_to(monday.native, monday.native.size.width / 2 + 6, 0).perform
    assert_no_selector ".timeline-insert"
    pointer.release.perform

    wait_for_turbo
    assert_no_text "now runs"
    assert_equal [ @a, @b, @c ].map(&:id), queue_order
  end

  test "Esc cancels a drag, and letting go over the bar doesn't open it" do
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    pointer.click_and_hold(bar(@a).native).move_by(40, 0).perform
    assert_selector ".timeline-insert"
    pointer.send_keys(:escape).perform
    assert_no_selector ".timeline-insert"
    pointer.move_to(bar(@a).native).release.perform

    wait_for_turbo
    assert_current_path planner_path(line: "D1", week: "2026-11-16")
    assert_no_field "Notes", with: "First" # the bar's Edit page
    assert_equal [ @a, @b, @c ].map(&:id), queue_order
  end

  test "clicking a bar still opens it, and the live plan can't be dragged while drafting" do
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo
    bar(@a).click
    assert_field "Notes", with: "First"

    PlanDraft.start!
    visit planner_path(line: "D1", week: "2026-11-16", plan: "live")
    wait_for_turbo
    assert_no_selector ".timeline-block[data-drop-url]"
    assert_no_selector ".queue-handle"
  end
end
