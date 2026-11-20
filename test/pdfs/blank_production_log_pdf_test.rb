require "test_helper"

class BlankProductionLogPdfTest < ActiveSupport::TestCase
  test "two pages of form 5.4.1.2 to fill in by hand" do
    pdf = BlankProductionLogPdf.new(line: lines(:d1)).render
    text = pdf.scan(/<([0-9a-f]+)>/).map { |(hex)| [ hex ].pack("H*") }.join.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8)

    [ "PRODUCTION LOG", "Line D1", "DESPATCH No.", "Previous documents and labels removed", "Yes  /  No", "MATERIALS LOADED",
      "Running total (kg)", BlankProductionLogPdf::REEL_ROWS.to_s, "Line cleared for the next micron", "Technician: signature and date",
      "Page 2 of 2" ].each { assert_includes text, _1 }
    assert_not_includes text, "Page 3"
  end
end
