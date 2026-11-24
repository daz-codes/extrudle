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

  def queue_order
    lines(:d1).schedule_blocks.reload.ordered.map(&:id)
  end

  test "drag a bar onto an earlier one and the queue reorders" do
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    # Picked up at its middle (11:00, an hour in) and dropped on the middle of the
    # first bar (07:00): the new start, 06:00, is before the first bar's midpoint.
    bar(@c).drag_to(bar(@a))
    assert_text "No orders now runs Mon 16 Nov 06:00 – 08:00"
    assert_equal [ @c, @a, @b ].map(&:id), queue_order
    assert_selector "#planner_board tbody tr:first-child", text: "Third"
  end

  test "drag a queue row by its handle" do
    visit planner_path(line: "D1", week: "2026-11-16")
    wait_for_turbo

    find("#schedule_block_#{@b.id} .queue-handle").drag_to(find("#schedule_block_#{@a.id}"))
    assert_text "Changeover now runs Mon 16 Nov 06:00 – 08:00"
    assert_equal [ @b, @a, @c ].map(&:id), queue_order
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
