require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "defaults to the office role" do
    user = User.new(name: "New Person", email_address: "new@example.com", password: "long-enough")
    assert user.office?
    assert user.valid?
  end

  test "rejects an unknown role" do
    user = users(:office)
    user.role = "boss"
    assert_not user.valid?
    assert user.errors.of_kind?(:role, :inclusion)
  end

  test "requires a name and normalises whitespace" do
    user = User.new(name: "  Ann   Smith ", email_address: " ANN@Example.com ", password: "long-enough")
    assert_equal "Ann Smith", user.name
    assert_equal "ann@example.com", user.email_address

    user.name = " "
    assert_not user.valid?
  end

  test "requires passwords of at least 8 characters" do
    user = User.new(name: "Short", email_address: "short@example.com", password: "short")
    assert_not user.valid?
  end

  test "office access is for admin and office users only" do
    assert users(:admin).office_access?
    assert users(:office).office_access?
    assert_not users(:floor).office_access?
  end

  test "active scope excludes deactivated users" do
    assert_not_includes User.active, users(:deactivated)
  end

  test "initials" do
    assert_equal "EK", users(:floor).initials
  end
end
