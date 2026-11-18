require "test_helper"

class FloorControllerTest < ActionDispatch::IntegrationTest
  test "any signed-in user can open the floor screen" do
    %i[ admin office floor ].each do |name|
      sign_in_as users(name)
      get floor_root_path
      assert_response :success
      sign_out
    end
  end

  test "floor screen only links back to the office for office users" do
    sign_in_as users(:floor)
    get floor_root_path
    assert_select "a", text: "Office", count: 0
  end
end
