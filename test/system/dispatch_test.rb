require "application_system_test_case"

class DispatchTest < ApplicationSystemTestCase
  include ScheduleTestHelper
  include DispatchTestHelper

  test "make a delivery note from finished pallets, dispatch it and export it to Sage" do
    order_line = sales_order_lines(:bf_open_700)
    order_line.product_spec.update_columns(reels_per_pallet: 2)
    order_line.update_columns(price_per_tonne_cents: 165_000)
    order_line.sales_order.customer.update!(sage_account_ref: "BRIGHT01")
    run = run_with_pallets(pallets: [ [ 500, 500 ], [ 400 ] ], finish: true)
    sign_in users(:office)

    click_on "Dispatch"
    within("#ready_sales_order_#{order_line.sales_order.id}") { click_on "New delivery note" }
    uncheck "Pallet #{run.despatch_number}/2"
    fill_in "Haulier", with: "Pennine Haulage"
    click_on "Create delivery note"
    assert_text "Delivery note DN-00001 created"
    assert_text "1,000 kg"
    assert_text "£1,650.00"

    click_on "Mark dispatched"
    assert_text "DN-00001 is dispatched."
    assert_button "Back to draft"

    click_on "← Dispatch"
    within("#ready_sales_order_#{order_line.sales_order.id}") { assert_text "1" }
    click_on "Sage export (1)"
    accept_confirm { click_on "Export 1 note" }
    assert_text "Exported 1 delivery note"
    assert_selector "a", text: /sage-invoices-.*\.csv/
  end
end
