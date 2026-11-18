require "application_system_test_case"

class SalesOrdersTest < ApplicationSystemTestCase
  setup { sign_in users(:office) }

  test "create an order and add a line with the spec preview and tonnes" do
    click_on "Orders"
    click_on "New order"
    select "Brightform Packaging Ltd", from: "Customer"
    fill_in "Customer PO ref", with: "m20001"
    fill_in "Required by", with: (Date.current + 14)
    check "Urgent"
    click_on "Create Sales order"

    assert_text "Order SO-00005 was created"
    assert_text "No lines yet"

    select "BF-700-250", from: "Spec"
    within "turbo-frame#spec_summary" do
      assert_text ".250"
      assert_text "Underside 0.5%"
    end
    fill_in "Quantity", with: "12.5"
    choose "tonnes"
    click_on "Add line"

    assert_text "Added BF-700-250 to SO-00005"
    within "#lines-heading + table" do
      assert_text "12.50 t"
    end

    click_on "Orders"
    assert_selector "tr", text: "M20001"
  end
end
