require "test_helper"

class StockVariancesControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper
  include MaterialTestHelper

  test "lists bags on the lines, waiting and reconciled" do
    run = start_run
    on_line = load_bag(run, lots(:jade_opening)).lot
    waiting = load_bag(run, lots(:regrind_bag)).lot
    Stock::Reconciliation.mark_empty(waiting)
    reconciled = bag(materials(:jade))
    Stock::Reconciliation.mark_empty(reconciled)

    sign_in_as users(:office)
    get stock_variance_path
    assert_response :success
    assert_select "#on-lines-heading + table td", on_line.code
    assert_select "#waiting-heading + table td", waiting.code
    assert_select "section[aria-labelledby=variance-heading] td", reconciled.code
    assert_select "section[aria-labelledby=variance-heading] .badge", "Check"
  end

  test "is for the office" do
    sign_in_as users(:floor)
    get stock_variance_path
    assert_redirected_to floor_root_path
  end
end
