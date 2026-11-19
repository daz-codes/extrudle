require "test_helper"

class HomeControllerTest < ActionDispatch::IntegrationTest
  test "requires sign in" do
    get root_path
    assert_redirected_to new_session_path
  end

  test "office users see the home page" do
    sign_in_as users(:office)
    get root_path
    assert_response :success
    assert_select "h1", /Jess/
    assert_select "nav a", text: "Users", count: 0
  end

  test "the home cards link to their sections" do
    sign_in_as users(:office)
    get root_path
    [ planner_path, sales_orders_path, production_runs_path, stock_path, purchase_orders_path, master_data_path ].each do |path|
      assert_select "main a.card[href=?]", path
    end
  end

  test "pages load no fonts or styles from outside hosts" do
    get new_session_path
    assert_select "link[href^='http']", count: 0
    assert_select "script[src^='http']", count: 0
  end

  test "admins see the users link" do
    sign_in_as users(:admin)
    get root_path
    assert_select "nav a", text: "Users"
  end

  test "floor users are sent to the floor screen" do
    sign_in_as users(:floor)
    get root_path
    assert_redirected_to floor_root_path
  end
end
