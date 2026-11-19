require "test_helper"

class DeliveryNotePdfTest < ActiveSupport::TestCase
  include ScheduleTestHelper
  include DispatchTestHelper

  def pdf_text(note)
    DeliveryNotePdf.new(note.reload).render.scan(/<([0-9a-f]+)>/).map { |(hex)| [ hex ].pack("H*") }.join
      .force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8)
  end

  test "prints the note with its pallets, totals and a box to sign" do
    order_line = sales_order_lines(:bf_open_700)
    order_line.product_spec.update_columns(reels_per_pallet: 2, customer_part_no: "BF-2231")
    run = run_with_pallets(pallets: [ [ "500.5", 500 ], [ 400 ] ], finish: true)
    note = delivery_note_for(run, [ 1, 2 ])
    note.update!(haulier: "Pennine Haulage", vehicle_reg: "YX24 KLM", delivery_address: "Unit 9\nLeeds LS1 1AA", notes: "Deliver before noon")

    text = pdf_text(note)
    [ "DELIVERY NOTE", note.number, "DRAFT: not yet dispatched", order_line.sales_order.number, "Pennine Haulage", "YX24 KLM",
      "Leeds LS1 1AA", "#{run.despatch_number}/1", "#{run.despatch_number}/2", "Part BF-2231", "1–2", "1,000.5", "1,400.5",
      "2 pallets", "Deliver before noon", "RECEIVED IN GOOD CONDITION" ].each { assert_includes text, _1 }

    note.mark_dispatched!
    assert_not_includes pdf_text(note), "DRAFT"
  end
end
