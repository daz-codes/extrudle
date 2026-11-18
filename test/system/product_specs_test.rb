require "application_system_test_case"

class ProductSpecsTest < ApplicationSystemTestCase
  setup { sign_in users(:office) }

  test "add a spec, set a line rate, then duplicate it" do
    click_on "Master data"
    within("nav[aria-label='Master data']") { click_on "Specs" }
    click_on "Add spec"

    fill_in "Spec code", with: "gp-750-275"
    select "Brightform Packaging Ltd", from: "Customer"
    fill_in "Thickness", with: "275"
    fill_in "Width", with: "750"

    assert_no_field "Silicone %"
    choose "Underside"
    fill_in "Silicone %", with: "0.4"

    fill_in "Max diameter", with: "1000"
    fill_in "Max reel weight", with: "1,050"
    click_on "Create Product spec"

    assert_text "Spec GP-750-275 was added."
    assert_selector "td", text: ".275"
    assert_text "Underside 0.4%"
    assert_text "1,050 kg"

    within "#rate_line_#{lines(:d1).id}" do
      fill_in "Rate on D1", with: "200"
      click_on "Save"
    end
    assert_text "Rate for line D1 saved."

    click_on "Duplicate as new"
    assert_text "Copied from GP-750-275"
    assert_field "Width", with: "750"
    fill_in "Spec code", with: "GP-800-275"
    fill_in "Width", with: "800"
    click_on "Create Product spec"

    assert_text "Spec GP-800-275 was added."
    assert_field "Rate on D1", with: "200"
  end

  test "max diameter is hidden for max roll on side" do
    visit new_product_spec_path
    assert_field "Max diameter"
    choose "Max roll on side"
    assert_no_field "Max diameter"
  end
end
