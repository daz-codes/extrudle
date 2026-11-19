require "application_system_test_case"

class PurchaseOrdersTest < ApplicationSystemTestCase
  setup { sign_in users(:office) }

  test "raise a PO, add lines, send it and take it back to draft" do
    click_on "Purchasing"
    click_on "New purchase order"
    wait_for_turbo
    select "Pacific Resin Exports", from: "Supplier"
    fill_in "Expected delivery", with: (Date.current + 21)
    fill_in "Supplier ref", with: "PRE-Q-1"
    click_on "Create Purchase order"

    assert_text "PO-00004 was created"
    within("section", text: /incoterm/i) { assert_text "CIF" }

    select "JADE · CZ-302", from: "Material"
    fill_in "Quantity", with: "22"
    choose "tonnes"
    fill_in "Price per tonne", with: "1,240"
    click_on "Add line"

    assert_text "Added JADE · CZ-302 to PO-00004"
    within("#lines-heading + table") { assert_text "$27,280.00" }

    accept_confirm { click_on "Mark as sent" }
    assert_text "PO-00004 is marked as sent"
    assert_no_button "Add line"
    assert_link "Download PDF"

    accept_confirm { click_on "Back to draft" }
    assert_text "PO-00004 is back to draft"
    assert_button "Add line"
  end
end
