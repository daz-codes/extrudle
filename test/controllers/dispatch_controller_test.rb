require "test_helper"

class DispatchControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper
  include DispatchTestHelper

  setup do
    @order_line = sales_order_lines(:bf_open_700)
    @order = @order_line.sales_order
    @order_line.product_spec.update_columns(reels_per_pallet: 2)
    @order_line.update_columns(price_per_tonne_cents: 165_000)
    @order.customer.update!(sage_account_ref: "BRIGHT01")
    @run = run_with_pallets(pallets: [ [ 500, 500 ], [ 400 ] ], finish: true)
    sign_in_as users(:office)
  end

  test "the dispatch page lists orders with pallets ready" do
    get dispatch_path
    assert_select "#ready_sales_order_#{@order.id}", /#{@order.number}.*2.*1,400 kg/m
    assert_select "a[href=?]", new_delivery_note_path(order: @order.id), text: "New delivery note"
  end

  test "create a delivery note from ticked pallets, edit it, print it" do
    get new_delivery_note_path(order: @order.id)
    assert_select "input[name='pallets[]'][checked]", 2

    post delivery_notes_path, params: { pallets: [ "#{@run.id}-1" ], delivery_note: { sales_order_id: @order.id, haulier: "Pennine Haulage",
                                                                                   vehicle_reg: "yx24 klm", delivery_address: "Unit 9" } }
    note = DeliveryNote.last
    assert_redirected_to note
    assert_equal [ [ @run.id, 1 ] ], note.note_pallets.map { [ _1.production_run_id, _1.pallet_no ] }
    assert_equal "Pennine Haulage", note.haulier

    get edit_delivery_note_path(note)
    assert_select "input[name='pallets[]']", 2

    patch delivery_note_path(note), params: { pallets: [ "#{@run.id}-1", "#{@run.id}-2" ], delivery_note: { haulier: "Own lorry" } }
    assert_redirected_to note
    assert_equal [ 1, 2 ], note.reload.note_pallets.map(&:pallet_no)

    get delivery_note_path(note, format: :pdf)
    assert_equal "application/pdf", response.media_type
    assert_match "#{note.number}-draft.pdf", response.headers["Content-Disposition"]
  end

  test "a note needs a pallet, and only pallets offered can be added" do
    post delivery_notes_path, params: { pallets: [ "999-1" ], delivery_note: { sales_order_id: @order.id } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Choose at least one pallet/
    assert_equal 0, DeliveryNote.count
  end

  test "mark dispatched, undo, and the order page shows deliveries" do
    note = delivery_note_for(@run, [ 1, 2 ])
    patch mark_dispatched_delivery_note_path(note), params: { dispatched_on: Date.current.iso8601 }
    assert_redirected_to note
    assert note.reload.dispatched?
    assert_match "#{note.number} is dispatched", flash[:notice]

    get edit_delivery_note_path(note)
    assert_redirected_to note

    get sales_order_path(@order)
    assert_select "section[aria-labelledby=deliveries-heading]", /1.4 t of 10,000 kg gone/
    assert_select "button", "Mark dispatched"

    patch undo_dispatch_delivery_note_path(note)
    assert note.reload.draft?

    delete delivery_note_path(note)
    assert_not DeliveryNote.exists?(note.id)
  end

  test "an order that went out short is marked dispatched by hand" do
    delivery_note_for(@run, [ 1, 2 ], dispatch: true)
    patch mark_dispatched_sales_order_path(@order)
    assert @order.reload.dispatched?
  end

  test "export to Sage, then download the file again" do
    note = delivery_note_for(@run, [ 1 ], dispatch: true)
    get sage_exports_path
    assert_select "button", "Export 1 note"

    post sage_exports_path
    assert_redirected_to sage_exports_path
    export = SageExport.last
    assert_equal export, note.reload.sage_export

    get sage_export_path(export)
    assert_equal "text/csv", response.media_type
    assert response.body.start_with?("Type,Account Reference")
    assert_match export.filename, response.headers["Content-Disposition"]

    post sage_exports_path
    assert_equal "There's nothing ready to export", flash[:alert]
  end

  test "dispatch is office work" do
    sign_in_as users(:floor)
    get dispatch_path
    assert_redirected_to floor_root_path
    post sage_exports_path
    assert_equal 0, SageExport.count
  end

  test "customers take a Sage account reference and VAT code" do
    customer = @order.customer
    patch customer_path(customer), params: { customer: { sage_account_ref: "bright02", sage_tax_code: "T4" } }
    assert_equal [ "BRIGHT02", "T4" ], customer.reload.values_at(:sage_account_ref, :sage_tax_code)
  end
end
