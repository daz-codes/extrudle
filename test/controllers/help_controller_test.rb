require "test_helper"

class HelpControllerTest < ActionDispatch::IntegrationTest
  test "floor users get the floor topics in the floor layout" do
    sign_in_as users(:floor)
    get help_path
    assert_response :success
    assert_select "#reels h2", "Enter reels"
    assert_select "#down"
    assert_select "#planner", count: 0
    assert_select "#admin", count: 0
  end

  test "office users also get the office topics; admins the admin ones" do
    sign_in_as users(:office)
    get help_path
    assert_select "#dispatch h2", "Dispatch and Sage"
    assert_select "#admin", count: 0

    sign_in_as users(:admin)
    get help_path
    assert_select "#admin"
  end

  test "the blank paper log downloads for anyone, for a line or not" do
    sign_in_as users(:floor)
    get floor_root_path
    assert_select "a[href=?]", blank_production_runs_path(format: :pdf)

    get blank_production_runs_path(format: :pdf, line: lines(:d1).id)
    assert_equal "application/pdf", response.media_type
    assert_match "blank-production-log-d1.pdf", response.headers["Content-Disposition"]
  end
end
