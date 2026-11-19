require "application_system_test_case"

class ApprovedComputersSystemTest < ApplicationSystemTestCase
  setup do
    @was = Rails.configuration.x.require_approved_computers
    Rails.configuration.x.require_approved_computers = true
    users(:admin).update!(sign_in_anywhere: true)
  end

  teardown { Rails.configuration.x.require_approved_computers = @was }

  test "Stu approves a new computer, then the office can use it" do
    visit new_session_path
    assert_text "This computer isn't approved for Extrudle"

    fill_in "Email address", with: users(:office).email_address
    fill_in "Password", with: "password"
    click_on "Sign in"
    assert_text "This computer isn't approved for Extrudle. Ask an admin to approve it."

    sign_in users(:admin)
    click_on "Users"
    click_on "Computers"
    fill_in "Name", with: "Office PC"
    click_on "Approve this computer"
    assert_text "This computer is approved as Office PC."
    assert_selector ".badge", text: "This computer"

    click_on "Sign out"
    assert_no_text "This computer isn't approved"
    sign_in users(:office)
    assert_text "Good to see you"
  end
end
