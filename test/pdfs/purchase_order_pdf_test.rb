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
end
