require "application_system_test_case"

class SignInTest < ApplicationSystemTestCase
  test "office user signs in and out" do
    sign_in users(:office)
    assert_text "Good to see you, Olivia"

    click_on "Sign out"
    assert_selector "h1", text: "Sign in"
  end

  test "floor user lands on the floor screen" do
    sign_in users(:floor)
    assert_selector "h1", text: "Plant floor"
  end

  test "admin adds a floor user" do
    sign_in users(:admin)
    click_on "Users"
    click_on "Add user"

    fill_in "Name", with: "Nina Nights"
    fill_in "Email address", with: "nina@example.com"
    choose "user_role_floor"
    fill_in "Password", with: "night-shift-1"
    fill_in "Repeat password", with: "night-shift-1"
    click_on "Add user"

    assert_text "Nina Nights was added."
    assert_selector "td", text: "nina@example.com"
  end
end
