require "application_system_test_case"

# Goods in on the floor (Slice 12).
class FloorGoodsInTest < ApplicationSystemTestCase
  test "an operator receives a delivery and gets its labels" do
    sign_in users(:floor)
    click_on "Goods in"
    click_on "Albion" # PO-00002
    click_on "Receive goods"
    wait_for_turbo

    codes = Lot.next_codes(2) # lot codes carry the year
    fill_in "Total net weight", with: "1,100"
    fill_in "Number of bags", with: "2"
    fill_in "First bag no.", with: "939"
    fill_in "Supplier batch no.", with: "CZ-77"
    click_on "Receive goods"

    assert_text "Received 2 bags of JADE as #{codes.first} to #{codes.last}. Print their labels below."
    within "section[aria-labelledby=received_today]" do
      assert_text "Bag 940"
      assert_link "Print labels"
    end
    assert_text "1,100 kg of 1,100 kg in"
  end
end
