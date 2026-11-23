require "test_helper"

class ScheduleBlocksControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper

  setup do
    travel_to at("2026-11-16 05:00")
    sign_in_as users(:office)
    @d1 = lines(:d1)
    @order_line = sales_order_lines(:bf_open_700)
  end

  def stream_post(path, params)
    post path, params: params, as: :turbo_stream
  end

  test "add a job from an order line, as a Turbo Stream" do
    stream_post schedule_blocks_path, { line_id: @d1.id, sales_order_line_id: @order_line.id, planned_kg: "1,900",
                                        queue_starts_at: "2026-11-16T06:00", week: "2026-11-16" }
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match(/turbo-stream action="replace" target="planner_board"/, response.body)
    assert_match(/Added SO-00001 BF-700-250 to line D1/, response.body)

    job = @d1.schedule_blocks.sole
    assert_equal [ 1_900_000, 600, at("2026-11-16 06:00") ], [ job.planned_g, job.duration_minutes, job.starts_at ]
  end

  test "adding a job with no rate needs hours" do
    order_line = stock_order_line
    stream_post schedule_blocks_path, { line_id: @d1.id, sales_order_line_id: order_line.id }
    assert_response :success # added with the default one-slot estimate...
    job = @d1.schedule_blocks.sole
    assert_equal 30, job.duration_minutes

    stream_post schedule_blocks_path, { line_id: lines(:d2).id, sales_order_line_id: @order_line.id, planned_kg: "1000", duration_hours: "1.25" }
    assert_response :success, "hours are ignored when there's a rate"
  end

  test "add a locked maintenance block at a time" do
    stream_post schedule_blocks_path, { line_id: @d1.id, kind: "planned_maintenance", duration_hours: "4", locked: "1",
                                        starts_at: "2026-11-17T14:00", notes: "Screw inspection" }
    block = @d1.schedule_blocks.sole
    assert block.locked?
    assert_equal [ at("2026-11-17 14:00"), at("2026-11-17 18:00"), "Screw inspection" ], [ block.starts_at, block.ends_at, block.notes ]
  end

  test "bad input comes back as an alert on the board" do
    stream_post schedule_blocks_path, { line_id: @d1.id, kind: "nap", duration_hours: "1" }
    assert_response :unprocessable_content
    assert_match(/Choose what kind of block to add/, response.body)

    stream_post schedule_blocks_path, { line_id: @d1.id, kind: "no_orders", duration_hours: "1.25" }
    assert_response :unprocessable_content
    assert_match(/multiple of 30 minutes/, response.body)

    stream_post schedule_blocks_path, { line_id: @d1.id, kind: "no_orders", duration_hours: "lots" }
    assert_match(/number of hours/, response.body)
    assert_empty @d1.schedule_blocks
  end

  test "insert at a position" do
    editor = Schedule::Editor.new(@d1)
    first = editor.add(block("no_orders", 60), starts_at: at(MONDAY_6AM))
    stream_post schedule_blocks_path, { line_id: @d1.id, kind: "changeover", duration_hours: "1", position: "1" }
    assert_equal %w[changeover no_orders], @d1.schedule_blocks.ordered.map(&:kind)
    assert_equal at("2026-11-16 07:00"), first.reload.starts_at
  end

  test "move up and down" do
    editor = Schedule::Editor.new(@d1)
    a = editor.add(block("no_orders", 60), starts_at: at(MONDAY_6AM))
    b = editor.add(block("changeover", 30))

    patch move_schedule_block_path(b, direction: "up"), as: :turbo_stream
    assert_response :success
    assert_equal [ b, a ].map(&:id), @d1.schedule_blocks.ordered.map(&:id)

    patch move_schedule_block_path(b, direction: "down")
    assert_redirected_to planner_path(line: "D1", week: "2026-11-16")
    assert_equal [ a, b ].map(&:id), @d1.schedule_blocks.ordered.map(&:id)
  end

  test "remove a job and the order goes back to open" do
    job = Schedule::Editor.new(@d1).add_job(@order_line, starts_at: at(MONDAY_6AM))
    assert @order_line.sales_order.reload.scheduled?

    delete schedule_block_path(job), as: :turbo_stream
    assert_response :success
    assert_empty @d1.schedule_blocks
    assert @order_line.sales_order.reload.open?
  end

  test "automatic changeovers can't be removed" do
    editor = Schedule::Editor.new(@d1)
    editor.add_job(@order_line, planned_g: 190_000, starts_at: at(MONDAY_6AM))
    editor.add_job(stock_order_line)
    changeover = @d1.schedule_blocks.changeover.sole

    delete schedule_block_path(changeover), as: :turbo_stream
    assert_response :unprocessable_content
    assert_match(/added automatically/, response.body)
  end

  test "edit and update a job's weight, notes and lock" do
    job = Schedule::Editor.new(@d1).add_job(@order_line, planned_g: 1_900_000, starts_at: at(MONDAY_6AM))
    get edit_schedule_block_path(job)
    assert_response :success
    assert_select "input[name=planned_kg][value='1900']"

    patch schedule_block_path(job), params: { planned_kg: "3800", notes: "Run first", locked: "1", starts_at: "2026-11-16T08:00" }
    assert_redirected_to planner_path(line: "D1", week: "2026-11-16")
    job.reload
    assert_equal [ 3_800_000, 1_200, "Run first", true, at("2026-11-16 08:00") ], [ job.planned_g, job.duration_minutes, job.notes, job.locked?, job.starts_at ]

    patch schedule_block_path(job), params: { locked: "0", planned_kg: "3800" }
    assert_not job.reload.locked?
  end

  test "update errors re-render the form" do
    gap = Schedule::Editor.new(@d1).add(block("no_orders", 60), starts_at: at(MONDAY_6AM))
    patch schedule_block_path(gap), params: { duration_hours: "0.75" }
    assert_response :unprocessable_content
    assert_select "#alert", /multiple of 30/
    assert_equal 60, gap.reload.duration_minutes
  end

  # --- Review fixes ---

  test "a job for a dispatched order can't be locked, unlocked or re-noted from the form" do
    job = Schedule::Editor.new(@d1).add_job(@order_line, planned_g: 1_900_000, starts_at: at(MONDAY_6AM))
    @order_line.sales_order.update_column(:status, "dispatched")

    get edit_schedule_block_path(job)
    assert_select "input[name=locked][disabled]", count: 2
    assert_select "textarea[name=notes][disabled]"
    assert_select "input[type=submit]", count: 0

    patch schedule_block_path(job), params: { locked: "1", starts_at: "2026-11-17T08:00", notes: "Moved" }
    assert_response :unprocessable_content
    assert_select "#alert", /dispatched, so its plan can't change/
    job.reload
    assert_not job.locked?
    assert_nil job.notes
    assert_equal at(MONDAY_6AM), job.starts_at
  end

  test "weight and lock saved together land where asked, in one edit" do
    editor = Schedule::Editor.new(@d1)
    job = editor.add_job(@order_line, planned_g: 1_900_000, starts_at: at(MONDAY_6AM)) # 10 h
    editor.add(block("planned_maintenance", 60, locked: true, starts_at: at("2026-11-16 20:00")))

    patch schedule_block_path(job), params: { planned_kg: "3800", locked: "1", starts_at: "2026-11-17T08:00" }
    assert_redirected_to planner_path(line: "D1", week: "2026-11-16")
    assert_equal [ at("2026-11-17 08:00"), at("2026-11-18 04:00") ], [ job.reload.starts_at, job.ends_at ]
  end

  test "a new locked block at an off-slot time is snapped, like locking an existing one" do
    stream_post schedule_blocks_path, { line_id: @d1.id, kind: "planned_maintenance", duration_hours: "1", locked: "1",
                                        starts_at: "2026-11-17T14:15" }
    assert_response :success
    assert_equal at("2026-11-17 14:30"), @d1.schedule_blocks.sole.starts_at
  end

  test "a planned weight of 0 says so" do
    stream_post schedule_blocks_path, { line_id: @d1.id, sales_order_line_id: @order_line.id, planned_kg: "0" }
    assert_response :unprocessable_content
    assert_match(/Planned weight must be more than 0/, response.body)
  end

  test "a failed add shows the line's real queue start" do
    Schedule::Editor.new(@d1).add(block("planned_maintenance", 60, locked: true, starts_at: at("2026-11-16 06:00")))
    stream_post schedule_blocks_path, { line_id: @d1.id, kind: "no_orders", duration_hours: "0.75",
                                        queue_starts_at: "2026-11-23T06:00", week: "2026-11-16" }
    assert_response :unprocessable_content
    assert_nil @d1.reload.queue_starts_at
    assert_no_match(/Starts Mon 23 Nov/, response.body)
  end

  test "the timeline lists this week's warnings in full, for touch screens" do
    Schedule::Editor.new(@d1).add_job(stock_order_line, starts_at: at(MONDAY_6AM)) # no rate on D1
    get planner_path(line: "D1", week: "2026-11-16")
    assert_select "h3", text: "Warnings this week"
    assert_select "h3 + ul a", text: /No rate.*so 30m is an estimate/m
  end

  test "a job's colour: the customer's by default, its own if picked, and back again" do
    customers(:brightform).update!(colour: "cherry")
    job = Schedule::Editor.new(@d1).add_job(@order_line, planned_g: 1_900_000, starts_at: at(MONDAY_6AM))
    get planner_path(line: "D1", week: "2026-11-16")
    assert_select ".timeline-block.job-colour-cherry"

    get edit_schedule_block_path(job)
    assert_select "input[type=radio][name=colour]", JobColour::NAMES.size
    assert_select "input[type=radio][name=colour][value=cherry][checked]"

    patch schedule_block_path(job), params: { colour: "pistachio", planned_kg: "1900" }
    assert_equal "pistachio", job.reload.colour
    get planner_path(line: "D1", week: "2026-11-16")
    assert_select ".timeline-block.job-colour-pistachio"

    get edit_schedule_block_path(job)
    assert_select "input[type=radio][name=colour][value=pistachio][checked]"

    # Back to the customer's colour: stored as nil, so it follows the customer.
    patch schedule_block_path(job), params: { colour: "cherry", planned_kg: "1900" }
    assert_nil job.reload.colour
    customers(:brightform).update!(colour: "mango")
    assert_equal "mango", JobColour.for(job.reload)
  end
end
