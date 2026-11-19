require "test_helper"

class ApprovedComputersTest < ActionDispatch::IntegrationTest
  setup do
    @was = Rails.configuration.x.require_approved_computers
    Rails.configuration.x.require_approved_computers = true
    users(:admin).update!(sign_in_anywhere: true)
  end

  teardown { Rails.configuration.x.require_approved_computers = @was }

  def sign_in(user, password: "password")
    post session_path, params: { email_address: user.email_address, password: }
  end

  def approve_this_computer(name = "Office PC")
    sign_in users(:admin)
    post admin_devices_path, params: { device: { name: } }
    delete session_path
    Device.find_by!(name:)
  end

  test "on an unapproved computer only a sign-in-anywhere admin can sign in" do
    get new_session_path
    assert_response :success
    assert_select "p", /This computer isn't approved for Extrudle/

    sign_in users(:office)
    assert_redirected_to new_session_path
    assert_equal "This computer isn't approved for Extrudle. Ask an admin to approve it.", flash[:alert]
    assert_not users(:office).sessions.exists?

    sign_in users(:admin)
    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "an admin approves the computer they're on, and then anyone can sign in there" do
    sign_in users(:admin)
    get admin_devices_path
    assert_select "input[type=submit][value=?]", "Approve this computer"

    post admin_devices_path, params: { device: { name: "D1 floor screen" } }
    assert_redirected_to admin_devices_path
    device = Device.sole
    assert_equal [ "D1 floor screen", users(:admin) ], [ device.name, device.approved_by ]
    assert cookies[Device::COOKIE].present?
    assert_not_includes device.attributes.values.map(&:to_s), cookies[Device::COOKIE], "only the digest is stored"

    follow_redirect!
    assert_select ".badge", "This computer"

    delete session_path
    sign_in users(:office)
    assert_redirected_to root_url
    follow_redirect!
    assert_response :success
  end

  test "revoking a computer signs it out at once" do
    device = approve_this_computer
    sign_in users(:office)
    get sales_orders_path
    assert_response :success

    device.revoke!(by: users(:admin))
    get sales_orders_path
    assert_response :forbidden
    assert_select "h1", "This computer isn't approved"
    assert_not users(:office).sessions.exists?
  end

  test "a signed-in user without sign-in-anywhere is stopped on an unapproved computer" do
    sign_in_as users(:office)
    get sales_orders_path
    assert_response :forbidden
  end

  test "password reset still works on an unapproved computer" do
    get new_password_path
    assert_response :success
  end

  test "admins can rename and revoke computers; others can't see them" do
    device = approve_this_computer
    sign_in users(:admin)
    patch admin_device_path(device), params: { device: { name: "Office laptop" } }
    assert_equal "Office laptop", device.reload.name

    patch revoke_admin_device_path(device)
    assert_not device.reload.approved?
    assert_equal users(:admin), device.revoked_by

    delete session_path
    approve_this_computer("Second PC")
    sign_in users(:office)
    get admin_devices_path
    assert_redirected_to root_path
  end

  test "an admin can't stop signing in anywhere from an unapproved computer" do
    sign_in users(:admin)
    patch admin_user_path(users(:admin)), params: { user: { sign_in_anywhere: "0" } }
    assert_response :unprocessable_content
    assert users(:admin).reload.sign_in_anywhere?
  end

  test "with approval switched off, any computer can be used" do
    Rails.configuration.x.require_approved_computers = false
    sign_in users(:office)
    assert_redirected_to root_url
  end

  test "a revoked computer asking for a download gets the not approved page, not an error" do
    device = approve_this_computer
    sign_in users(:office)
    device.revoke!(by: users(:admin))

    get purchase_order_path(purchase_orders(:pacific_draft), format: :pdf)
    assert_response :forbidden
    assert_equal "text/html", response.media_type
    assert_select "h1", "This computer isn't approved"
  end
end
