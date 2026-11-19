require "test_helper"

class ProductionRunTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  def start(block = planned_job, **attrs)
    ProductionRun::Start.new(schedule_block: block, **attrs).tap { _1.user = users(:floor) }
  end

  test "starting a log takes the next despatch number and puts the order in production" do
    s = start(technician_days: " Dave  Hirst ")
    assert_equal 1, s.despatch_number
    assert s.save, s.errors.full_messages.to_sentence

    run = s.run
    assert run.running?
    assert_equal [ lines(:d1), sales_order_lines(:bf_open_700), product_specs(:bf_700), users(:floor) ],
                 [ run.line, run.sales_order_line, run.product_spec, run.started_by ]
    assert_equal "Dave Hirst", run.technician_days
    assert sales_orders(:bf_open).reload.in_production?
    assert_equal 2, ProductionRun.next_despatch_number
  end

  test "the despatch number can carry on from the paper logs, and must be unique" do
    assert start(despatch_number: 731).save
    assert_equal 732, ProductionRun.next_despatch_number

    ProductionRun.running.update_all(status: "finished")
    duplicate = start(planned_job(sales_order_lines(:bf_overdue_700)), despatch_number: 731)
    assert_not duplicate.save
    assert duplicate.errors.of_kind?(:despatch_number, :taken)
  end

  test "special instructions come from the spec's packaging notes and the order notes" do
    product_specs(:bf_700).update_columns(packaging_notes: "Best-quality pallets only.")
    sales_orders(:bf_open).update_columns(notes: "Deliver to gate 2.")
    s = start
    assert s.save
    assert_equal "Best-quality pallets only.\nDeliver to gate 2.", s.run.special_instructions
  end

  test "one log at a time per line, one log per job" do
    job = planned_job
    assert start(job).save
    assert_not start(job).valid?
    other = start(planned_job(sales_order_lines(:bf_overdue_700)))
    assert_not other.save
    assert_match "already running despatch 1", other.errors.full_messages.to_sentence

    assert start(planned_job(stock_order_line, line: lines(:d2))).save
  end

  test "only jobs for orders still to make, and not in the future" do
    job = planned_job
    order = job.sales_order
    order.update_columns(status: "cancelled")
    assert_not start(job).valid?

    order.update_columns(status: "open")
    assert_not start(job, started_at: 1.hour.from_now).valid?
  end

  test "started_at from the form is UK time" do
    travel_to Time.zone.parse("2026-07-01 12:00") do
      s = start(started_at: "2026-07-01T06:00")
      assert_equal Time.utc(2026, 7, 1, 5, 0), s.started_at.utc
    end
  end

  test "a started job can't be taken off the plan" do
    job = planned_job
    start(job).save
    assert_raises(Schedule::Error) { Schedule::Editor.new(lines(:d1)).remove(job) }
  end

  test "starting one job keeps the rest of the order plannable, but the started job stays put" do
    order_line = sales_order_lines(:bf_open_700) # 10 t
    editor = Schedule::Editor.new(lines(:d1))
    job = editor.add_job(order_line, planned_g: 4_000_000)
    gap = editor.add(block("no_orders", 60))
    assert start(job).save
    assert sales_orders(:bf_open).reload.in_production?

    rest = editor.add_job(order_line.reload) # the other 6 t, on the same order
    assert_equal 6_000_000, rest.planned_g
    editor.move(rest, :up) # past the gap
    editor.update(job.reload, notes: "Running long")
    assert_equal "Running long", job.reload.notes

    error = assert_raises(Schedule::Error) { editor.move(job, :down) }
    assert_match "has started", error.message
    editor.move(gap.reload, :up) # queue: job, gap, rest
    assert_raises(Schedule::Error) { editor.move(gap.reload, :up) } # would swap with the started job
    assert_raises(Schedule::Error) { editor.remove(job) }
  end

  test "the database allows one running log per line" do
    assert start.save
    second = ProductionRun.new(line: lines(:d1), sales_order_line: sales_order_lines(:bf_overdue_700), product_spec: product_specs(:bf_700),
                               despatch_number: 99, started_at: Time.current)
    assert_raises(ActiveRecord::RecordNotUnique) { second.save(validate: false) }
    second.status = "finished"
    assert second.save(validate: false), "finished logs don't count"
  end

  test "two people starting the same job at once are told it already has a log" do
    job = planned_job
    s = start(job)
    s.define_singleton_method(:block_is_a_job_without_a_log) { } # the other user's log isn't visible yet
    assert start(job).save
    ProductionRun.update_all(status: "finished")
    assert_not s.save
    assert_equal [ "This job already has a production log" ], s.errors.full_messages
  end

  test "prestart answers: the latest counts, all are kept" do
    s = start
    s.save
    run = s.run
    assert_not run.prestart_complete?

    run.record_check(stage: "prestart", item: "previous_documents_removed", passed: "false", user: users(:floor))
    run.record_check(stage: "prestart", item: "previous_documents_removed", passed: "true", note: "Found old labels, removed")
    run.record_check(stage: "prestart", item: "previous_product_cleared", passed: true)
    run.reload
    assert run.prestart_complete?
    assert_equal 3, run.checks.size
    assert_equal "Found old labels, removed", run.answer("prestart", "previous_documents_removed").note

    assert_not run.record_check(stage: "prestart", item: "made_up", passed: true).persisted?
  end
end
