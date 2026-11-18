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
    assert_select "h1", /Olivia/
    assert_select "nav a", text: "Users", count: 0
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
