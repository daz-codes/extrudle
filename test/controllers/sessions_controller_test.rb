require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  setup { @user = users(:office) }

  test "new" do
    get new_session_path
    assert_response :success
  end

  test "create with valid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "password" }

    assert_redirected_to root_path
    assert cookies[:session_id]
  end

  test "floor users land on the floor screen" do
    post session_path, params: { email_address: users(:floor).email_address, password: "password" }
    assert_redirected_to floor_root_url
  end

  test "floor users ignore a stored office URL and land on the floor screen" do
    get root_path
    post session_path, params: { email_address: users(:floor).email_address, password: "password" }
    assert_redirected_to floor_root_url
  end

  test "office users return to the page they asked for" do
    get admin_users_path
    post session_path, params: { email_address: @user.email_address, password: "password" }
    assert_redirected_to admin_users_url
  end

  test "a session cookie stops working once its user is deactivated" do
    sign_in_as @user
    @user.update!(active: false)
    get root_path
    assert_redirected_to new_session_path
  end

  test "create with invalid credentials" do
    post session_path, params: { email_address: @user.email_address, password: "wrong" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "deactivated users cannot sign in" do
    post session_path, params: { email_address: users(:deactivated).email_address, password: "password" }

    assert_redirected_to new_session_path
    assert_nil cookies[:session_id]
  end

  test "destroy" do
    sign_in_as(@user)

    delete session_path

    assert_redirected_to new_session_path
    assert_empty cookies[:session_id]
  end
end
