require "test_helper"

class Admin::UsersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:admin) }

  test "index lists users" do
    get admin_users_path
    assert_response :success
    assert_select "td", text: "Fred Floor"
  end

  test "office and floor users are kept out" do
    sign_out
    sign_in_as users(:office)
    get admin_users_path
    assert_redirected_to root_path

    sign_out
    sign_in_as users(:floor)
    get admin_users_path
    assert_redirected_to floor_root_path
  end

  test "creates a user" do
    assert_difference "User.count" do
      post admin_users_path, params: { user: { name: "New Op", email_address: "op@example.com", role: "floor",
                                               active: "1", password: "long-enough", password_confirmation: "long-enough" } }
    end
    assert_redirected_to admin_users_path
    assert User.find_by(email_address: "op@example.com").floor?
  end

  test "re-renders the form on invalid input" do
    assert_no_difference "User.count" do
      post admin_users_path, params: { user: { name: "", email_address: "x@example.com", role: "office", password: "long-enough", password_confirmation: "long-enough" } }
    end
    assert_response :unprocessable_content
  end

  test "updates without changing the password when left blank" do
    user = users(:office)
    digest = user.password_digest
    patch admin_user_path(user), params: { user: { name: "Olivia O", role: "office", password: "", password_confirmation: "" } }
    assert_redirected_to admin_users_path
    assert_equal "Olivia O", user.reload.name
    assert_equal digest, user.password_digest
  end

  test "deactivating a user ends their sessions" do
    user = users(:office)
    user.sessions.create!
    patch admin_user_path(user), params: { user: { active: "0" } }
    assert_not user.reload.active?
    assert_empty user.sessions
  end

  test "admins cannot demote or deactivate themselves" do
    patch admin_user_path(users(:admin)), params: { user: { role: "office" } }
    assert_response :unprocessable_content
    assert users(:admin).reload.admin?

    patch admin_user_path(users(:admin)), params: { user: { active: "0" } }
    assert_response :unprocessable_content
    assert users(:admin).reload.active?
  end
end
