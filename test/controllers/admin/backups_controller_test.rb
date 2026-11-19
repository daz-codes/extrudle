require "test_helper"

class Admin::BackupsControllerTest < ActionDispatch::IntegrationTest
  test "admins see the backup status; checking needs backups set up" do
    BackupCheck.create!(ok: true, message: "Restored the latest backup and checked it: 99 rows across 10 tables")
    sign_in_as users(:admin)
    get admin_backups_path
    assert_response :success
    assert_select "[role=status]", /Last check passed/
    assert_select "span.badge", "Not set up"

    post admin_backups_path
    assert_match "aren't set up", flash[:alert]
  end

  test "office users can't" do
    sign_in_as users(:office)
    get admin_backups_path
    assert_redirected_to root_path
  end
end
