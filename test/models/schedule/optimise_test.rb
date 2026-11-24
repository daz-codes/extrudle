require "test_helper"

class Schedule::OptimiseTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  setup do
    travel_to at("2026-11-16 05:00")
    # Start from a clean slate: the fixture orders would otherwise be planned too.
    SalesOrder.active.update_all(status: "cancelled")
    @d1 = lines(:d1) # 60 minute changeovers
    @d2 = lines(:d2) # 90 minute changeovers
    @live = Schedule::Editor.new(@d1)
    @live.start_at(at(MONDAY_6AM))
    Schedule::Editor.new(@d2).start_at(at(MONDAY_6AM))
  end

  teardown { travel_back }

  # A spec running at 100 kg/h on the given lines, so 1,000 kg takes 10 hours.
  def spec(code, lines: [ @d1, @d2 ])
    spec = ProductSpec.create!(code:, revision: 1, width_mm: 700, thickness_micron: 250, core_inches: 6, max_diameter_mm: 1000)
    lines.each { spec.line_rates.create!(line: _1, kg_per_hour: 100) }
    spec
  end

  def order_line(spec, kg:, due:, urgent: false)
    order = SalesOrder.create!(customer: customers(:brightform), required_on: Date.parse(due), urgent:)
    order.lines.create!(product_spec: spec, quantity: kg.to_s)
  end

  def optimise(draft = PlanDraft.start!, seed: 1)
    Schedule::Optimise.new(draft.plan, random: Random.new(seed)).call
  end

  def draft_jobs(line)
    PlanDraft.current.plan.blocks_for(line).jobs.ordered.map { _1.sales_order.required_on.strftime("%d") + " " + _1.product_spec.code }
  end

  def draft_kinds(line)
    PlanDraft.current.plan.blocks_for(line).ordered.map(&:kind)
  end

  test "puts jobs in required-date order so none is late" do
    @d2.update!(active: false)
    a = spec("A-1")
    late = order_line(a, kg: 1_000, due: "2026-11-20")
    soon = order_line(a, kg: 1_000, due: "2026-11-16") # 10 hours, due today
    @live.add_job(late)
    @live.add_job(soon)

    result = optimise
    assert_equal [ "16 A-1", "20 A-1" ], draft_jobs(@d1)
    assert_equal 1, result.before.late_orders
    assert_equal 0, result.after.late_orders
    assert_equal [ late, soon ].map(&:id).sort, ScheduleBlock.live.jobs.pluck(:sales_order_line_id).sort, "the live plan doesn't change"
  end

  test "spreads jobs across both lines when one line can't make them all in time" do
    a = spec("A-1")
    first = order_line(a, kg: 1_500, due: "2026-11-16")  # 15 hours each, due today
    second = order_line(a, kg: 1_500, due: "2026-11-16")
    @live.add_job(first)
    @live.add_job(second)

    result = optimise
    assert_equal 1, draft_jobs(@d1).size
    assert_equal 1, draft_jobs(@d2).size
    assert_equal 0, result.after.late_orders
    assert_equal 1, result.moved
    assert_match "Moved 1 job to the other line.", result.summary
  end

  test "runs the same spec back to back when the dates allow, to save changeovers" do
    @d2.update!(active: false)
    a = spec("A-1")
    b = spec("B-1")
    order_line(a, kg: 500, due: "2026-11-30")
    order_line(b, kg: 500, due: "2026-11-30")
    order_line(a, kg: 500, due: "2026-11-30")
    3.times { |i| @live.add_job(SalesOrderLine.order(:id).last(3)[i]) }
    assert_equal 2, ScheduleBlock.live.where(kind: "changeover").count

    result = optimise
    assert_equal 1, result.after.changeovers
    assert_equal %w[ job job changeover job ], draft_kinds(@d1)
  end

  test "urgent jobs go first, whatever their dates" do
    @d2.update!(active: false)
    a = spec("A-1")
    @live.add_job(order_line(a, kg: 100, due: "2026-11-17"))
    @live.add_job(order_line(a, kg: 100, due: "2026-11-27", urgent: true))

    optimise
    assert_equal [ "27 A-1", "17 A-1" ], draft_jobs(@d1)
  end

  test "plans order lines that aren't on the plan, and says which have no rate anywhere" do
    a = spec("A-1")
    unplanned = order_line(a, kg: 300, due: "2026-11-18")
    no_rate = stock_order_line(kg: 100)

    result = optimise
    assert_equal 300_000, PlanDraft.current.plan.planned_g(unplanned)
    assert_equal 0, PlanDraft.current.plan.planned_g(no_rate)
    assert_equal 1, result.added
    assert_equal [ "#{no_rate.sales_order.number} STK-1000-500" ], result.unplannable
    assert_match "Planned 1 job for orders that weren't on the plan.", result.summary
  end

  test "keeps jobs on the lines that have a rate for their spec" do
    d1_only = spec("D1-ONLY", lines: [ @d1 ])
    2.times { @live.add_job(order_line(d1_only, kg: 1_500, due: "2026-11-16")) }

    result = optimise
    assert_equal 2, draft_jobs(@d1).size
    assert_empty draft_jobs(@d2)
    assert_equal 1, result.after.late_orders, "only one fits today, but neither can move to D2"
  end

  test "locked blocks stay put, started jobs keep their place, and planner changeovers go" do
    @d2.update!(active: false)
    a = spec("A-1")
    b = spec("B-1")
    started = @live.add_job(order_line(b, kg: 200, due: "2026-11-30"))
    @live.add(block("changeover", 120))
    @live.add_job(order_line(a, kg: 200, due: "2026-11-30"))
    @live.add_job(order_line(a, kg: 200, due: "2026-11-16"))
    visit = @live.add(block("planned_maintenance", 240, locked: true, starts_at: at("2026-11-16 12:00")))
    assert ProductionRun::Start.new(schedule_block: started).save

    optimise
    draft = PlanDraft.current.plan.blocks_for(@d1).ordered.to_a
    assert_equal started.id, draft.first.source_block_id
    copy = draft.detect { _1.source_block_id == visit.id }
    assert_equal [ at("2026-11-16 12:00"), true ], [ copy.starts_at, copy.locked? ]
    assert draft.select(&:changeover?).all?(&:automatic?)
    assert_equal 0, Schedule::Warnings.for_line(@d1, plan: PlanDraft.current.plan).values.flatten.count { _1.code == :late }
  end

  test "optimises the draft that's already open, and the same seed gives the same plan" do
    a = spec("A-1")
    4.times { |i| @live.add_job(order_line(a, kg: 400, due: "2026-11-2#{i}")) }
    draft = PlanDraft.start!

    optimise(draft, seed: 7)
    first = [ draft_jobs(@d1), draft_jobs(@d2) ]
    optimise(draft, seed: 7)
    assert_equal first, [ draft_jobs(@d1), draft_jobs(@d2) ]
    assert_equal 1, PlanDraft.count
  end

  test "a job moved to the other line is published there" do
    a = spec("A-1")
    first = @live.add_job(order_line(a, kg: 1_500, due: "2026-11-16"))
    @live.add_job(order_line(a, kg: 1_500, due: "2026-11-16"))

    draft = PlanDraft.start!
    optimise(draft)
    Schedule::Publish.new(draft).call
    assert_equal 1, @d1.schedule_blocks.jobs.count
    assert_equal 1, @d2.schedule_blocks.jobs.count
    assert_equal SalesOrderLine.last(2).map(&:id).sort, ScheduleBlock.live.jobs.pluck(:sales_order_line_id).sort
    assert PlanDraft.none?
  end

  test "won't touch the live plan" do
    assert_raises(ArgumentError) { Schedule::Optimise.new(Schedule::Plan.live) }
  end
end
