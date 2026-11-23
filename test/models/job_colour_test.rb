require "test_helper"

class JobColourTest < ActiveSupport::TestCase
  include ScheduleTestHelper

  setup do
    travel_to at(MONDAY_6AM)
    editor = Schedule::Editor.new(lines(:d1))
    @job = editor.add_job(sales_order_lines(:bf_open_700), starts_at: at(MONDAY_6AM))
    @urgent = editor.add_job(sales_order_lines(:bf_overdue_700))
  end

  test "no colour keeps lemon and lime: lime, or lemon if urgent" do
    assert_equal [ "lime", "lemon" ], [ JobColour.for(@job), JobColour.for(@urgent) ]
  end

  test "the customer's colour is the default, and a job's own colour wins" do
    customers(:brightform).update!(colour: "blueberry")
    assert_equal [ "blueberry", "blueberry" ], [ JobColour.for(@job.reload), JobColour.for(@urgent.reload) ]

    @job.update!(colour: "mango")
    assert_equal "mango", JobColour.for(@job)
  end

  test "colours must be on the list, blank means none, and only jobs have one" do
    customer = customers(:brightform)
    customer.colour = "puce"
    assert_not customer.valid?
    customer.colour = " "
    assert customer.valid?
    assert_nil customer.colour

    gap = Schedule::Editor.new(lines(:d2)).add(block("no_orders", 60), starts_at: at(MONDAY_6AM))
    gap.colour = "cherry"
    assert_not gap.valid?
  end

  test "a coloured urgent job gets a lemon stripe; a lemon one doesn't need it" do
    helpers = ApplicationController.helpers
    assert_no_match "timeline-urgent", helpers.block_classes(@urgent)

    customers(:brightform).update!(colour: "cherry")
    assert_match "timeline-urgent", helpers.block_classes(@urgent.reload)
    assert_no_match "timeline-urgent", helpers.block_classes(@job.reload), "only urgent jobs"

    @urgent.update!(colour: "lemon")
    assert_no_match "timeline-urgent", helpers.block_classes(@urgent)
  end

  test "every colour has a style" do
    css = Rails.root.join("app/assets/tailwind/application.css").read
    JobColour::NAMES.each { assert_includes css, ".#{JobColour.css_class(_1)} {" }
  end
end
