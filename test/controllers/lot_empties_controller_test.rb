require "test_helper"

class LotEmptiesControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper
  include MaterialTestHelper

  setup { sign_in_as users(:office) }

  test "marking a bag on a running log empty waits for the log, and can be undone" do
    run = start_run
    lot = load_bag(run, lots(:jade_opening)).lot

    post lot_empty_path(lot)
    assert_redirected_to lot_path(lot)
    follow_redirect!
    assert_select ".badge", "Marked empty"
    assert_match "once despatch #{run.despatch_number} is finished", response.body
    assert_select "#loads-heading ~ table td", run.despatch_number.to_s

    delete lot_empty_path(lot)
    assert_not lot.reload.emptied?
  end

  test "a bag that has never been on a line can't be marked empty" do
    lot = lots(:jade_opening)
    get lot_path(lot)
    assert_select "button", text: "Mark empty", count: 0

    post lot_empty_path(lot)
    assert_match "hasn't been on a line", flash[:alert]
    assert_not lot.reload.emptied?
  end

  test "a bag whose logs have finished is reconciled at once and can't be undone" do
    run = start_run
    lot = load_bag(run, lots(:jade_opening)).lot
    add_reels(run, 900)
    finish_cleanly(run)

    post lot_empty_path(lot)
    assert lot.reload.reconciled?
    assert_equal 0, lot.quantity_g

    delete lot_empty_path(lot)
    assert_match "already been reconciled", flash[:alert]
  end
end
