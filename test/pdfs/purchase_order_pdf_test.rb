require "test_helper"

class PurchaseOrderPdfTest < ActiveSupport::TestCase
  # Prawn writes text as hex strings (split up for kerning). Decoding and joining
  # them is enough to check what's printed.
  def pdf_text(order)
    PurchaseOrderPdf.new(order).render.scan(/<([0-9a-f]+)>/).map { |(hex)| [ hex ].pack("H*") }.join
      .force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8)
  end

  test "prints the PO, its lines and totals" do
    text = pdf_text(purchase_orders(:albion_sent))
    assert_includes text, "PURCHASE ORDER"
    assert_includes text, "PO-00002"
    assert_includes text, "Albion Polymers"
    assert_includes text, "1,100 kg"
    assert_includes text, "£1,185.50"
    assert_includes text, "£1,304.05"
    assert_includes text, "OC-1182"
    assert_not_includes text, "DRAFT"
  end

  test "drafts say so" do
    assert_includes pdf_text(purchase_orders(:pacific_draft)), "DRAFT PURCHASE ORDER"
  end

  test "characters Helvetica can't print are transliterated" do
    suppliers(:pacific).update!(contact_name: "Paweł Łukasz")
    assert_includes pdf_text(purchase_orders(:pacific_draft)), "Pawel Lukasz"
  end

  test "the supplier ref is transliterated too" do
    purchase_orders(:albion_sent).update_columns(supplier_ref: "Łódź-1")
    assert_includes pdf_text(purchase_orders(:albion_sent)), "Lódz-1" # ó is in Windows-1252; Ł and ź are not
  end

  test "long POs run onto more pages with the footer on each" do
    order = purchase_orders(:pacific_draft)
    40.times { order.lines.create!(material: order.lines.first.material, quantity_unit: "kg", quantity: "100", price_per_tonne: "1") }
    text = pdf_text(order.reload)
    assert_includes text, "Page 1 of 2"
    assert_includes text, "Page 2 of 2"
  end
end
