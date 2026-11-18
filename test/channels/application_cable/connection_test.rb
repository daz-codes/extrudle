require "test_helper"

class ApplicationCable::ConnectionTest < ActionCable::Connection::TestCase
  test "connects with an active user's session" do
    session = users(:office).sessions.create!
    cookies.signed[:session_id] = session.id
    connect
    assert_equal users(:office), connection.current_user
  end

  test "rejects a deactivated user's session" do
    cookies.signed[:session_id] = users(:deactivated).sessions.create!.id
    assert_reject_connection { connect }
  end

  test "rejects a missing session" do
    assert_reject_connection { connect }
  end
end
