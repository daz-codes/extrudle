require "test_helper"

class DeviceTest < ActiveSupport::TestCase
  test "approving makes a random token, stores only its digest, and finds it again" do
    device = Device.approve!(name: "  Office  PC ", approved_by: users(:admin), user_agent: "Chrome", ip: "10.0.0.5")
    assert_equal "Office PC", device.name
    assert_equal Device.digest(device.token), device.token_digest
    assert_equal device, Device.find_by_token(device.token)
    assert_nil Device.find_by_token("not-a-token")
    assert_nil Device.find_by_token(nil)
    assert_nil Device.find(device.id).token

    device.revoke!(by: users(:admin))
    assert_nil Device.find_by_token(device.token)
  end

  test "seen! records use at most every few minutes" do
    device = Device.approve!(name: "PC", approved_by: users(:admin), ip: "10.0.0.5")
    travel 1.minute
    assert_no_changes -> { device.reload.last_used_at } do
      device.seen!(ip: "10.0.0.5")
    end
    travel 10.minutes
    device.seen!(ip: "10.0.0.6")
    assert_equal "10.0.0.6", device.reload.last_ip
  end

  test "only admins can sign in from anywhere" do
    user = users(:office)
    user.sign_in_anywhere = true
    assert_not user.valid?
    assert_includes user.errors[:sign_in_anywhere], "is only for admins"
  end
end
