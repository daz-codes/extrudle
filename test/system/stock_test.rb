require "application_system_test_case"

class StockTest < ApplicationSystemTestCase
  setup { sign_in users(:office) }

  test "receive a delivery against a PO, move a bag and see stock on hand" do
    click_on "Purchasing"
    click_on "PO-00002"
    click_on "Receive goods"
    wait_for_turbo

    fill_in "Total net weight", with: "1,100"
    fill_in "Number of bags", with: "2"
    fill_in "First bag no.", with: "939"
    fill_in "Supplier batch no.", with: "CZ-77"
    click_on "Receive goods"

    assert_text "Received 2 bags of JADE as L-2026-000004 to L-2026-000005"
    assert_link "Print 2 labels"
    click_on "L-2026-000005"

    assert_text "Bag 940"
    click_on "Storage"
    assert_text "L-2026-000005 moved to storage"
    assert_text "Moved from on site to storage"

    click_on "Stock"
    within "#stock_material_#{materials(:jade).id}" do
      assert_text "1.55 t" # on site: 1,000 kg opening + 550 kg
      assert_text "550 kg"   # storage
    end
  end
end
