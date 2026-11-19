require "test_helper"

class SageExportTest < ActiveSupport::TestCase
  include ScheduleTestHelper
  include DispatchTestHelper

  setup do
    @order_line = sales_order_lines(:bf_open_700)
    @order = @order_line.sales_order
    @order_line.product_spec.update_columns(reels_per_pallet: 2)
    @order_line.update_columns(quantity_g: 1_400_000, price_per_tonne_cents: 165_000)
    @order.update_columns(customer_po_ref: "M15159, rev 2")
    @order.customer.update!(sage_account_ref: "bright01", sage_tax_code: "T1")
    @run = run_with_pallets(pallets: [ [ 500, 500 ], [ 400 ] ], finish: true)
  end

  test "one sales invoice row per spec on each note, in Sage 50's audit trail layout" do
    note = delivery_note_for(@run, [ 1, 2 ], dispatch: true)
    export = SageExport.create_from!(SageExport.ready_notes, user: users(:office))
    header, row, *rest = export.csv.split("\r\n")

    assert_empty rest
    assert_equal SageExport::HEADER.join(","), header
    assert_equal [ "SI", "BRIGHT01", "4000", "0", Date.current.strftime("%d/%m/%Y"), note.number,
                   "#{@order.number} #{@order_line.product_spec} 1400 kg", "2310.00", "T1", "462.00", "",
                   "\"M15159, REV 2\"", users(:office).name, "", "" ], row.split(/,(?=(?:[^"]*"[^"]*")*[^"]*\z)/, -1)
    assert_equal 1, export.rows_count
  end

  test "exporting marks the notes sent, and the order invoiced once it has gone in full" do
    note = delivery_note_for(@run, [ 1, 2 ], dispatch: true)
    assert @order.reload.dispatched?
    freeze_time do
      export = SageExport.create_from!(SageExport.ready_notes)
      assert_equal [ Time.current, export ], [ note.reload.exported_at, note.sage_export ]
    end
    assert @order.reload.invoiced?
    assert_raises(ArgumentError) { note.undo_dispatch! }
    assert_raises(SageExport::NothingToExport) { SageExport.create_from!(SageExport.ready_notes) }
  end

  test "a part delivery is exported but the order isn't invoiced until it's all gone" do
    delivery_note_for(@run, [ 1 ], dispatch: true)
    SageExport.create_from!(SageExport.ready_notes)
    assert @order.reload.in_production?
  end

  test "notes missing a Sage account or a price wait, with the reason" do
    note = delivery_note_for(@run, [ 1 ], dispatch: true)
    @order.customer.update!(sage_account_ref: nil)
    @order_line.update_columns(price_per_tonne_cents: nil)
    assert_equal [ "#{@order.customer.name} has no Sage account reference",
                   "#{@order_line.product_spec} has no price per tonne on #{@order.number}" ], note.reload.export_problems
    assert_empty SageExport.ready_notes
  end

  test "drafts aren't exported, and EU customers use their own tax code" do
    delivery_note_for(@run, [ 1 ])
    assert_empty SageExport.ready_notes

    @order.customer.update!(sage_tax_code: "T4")
    DeliveryNote.first.mark_dispatched!
    row = SageExport.create_from!(SageExport.ready_notes).csv.split("\r\n").last
    assert_match ",T4,0.00,", row
  end

  test "customers need a known tax code and a short, unique account reference" do
    customer = @order.customer
    customer.sage_tax_code = "T9"
    customer.sage_account_ref = "TOOLONGREF"
    assert_not customer.valid?
    assert customer.errors.key?(:sage_tax_code)
    assert customer.errors.key?(:sage_account_ref)
  end
end
