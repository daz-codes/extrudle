require "test_helper"

class ProductionLogPdfTest < ActiveSupport::TestCase
  include ScheduleTestHelper
  include MaterialTestHelper

  setup do
    @run = start_run
    @run.update!(technician_days: "Dave Hirst", antiblock_batch_no: "AB-5-2611")
    @run.record_check(stage: "prestart", item: "previous_documents_removed", passed: true, user: users(:floor))
    @run.record_measurement(stage: "startup", item: "thickness", actual: ".254")
    @jade = bag(materials(:jade), kg: 5_000, bag_no: "939")
    load_bag(@run, @jade)
    add_reels(@run, "1,042.5", "1,061")
  end

  def pdf_text(run, **options)
    ProductionLogPdf.new(run.reload, **options).render.scan(/<([0-9a-f]+)>/).map { |(hex)| [ hex ].pack("H*") }.join
      .force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8)
  end

  test "prints a running log like form 5.4.1.2, marked in progress" do
    text = pdf_text(@run, printed_by: users(:office))
    [ "PRODUCTION LOG", "Form 5.4.1.2", "DESPATCH No.", @run.despatch_number.to_s, "IN PROGRESS",
      "Brightform", "Dave Hirst", "AB-5-2611",
      "Previous documents and labels removed", "Yes", "Not answered",
      "254 µm", "238–262 µm", "Pass",
      "Virgin Main-Ex", "JADE", "939", @jade.code, "1 onwards", "Used so far, est.", "2,103.5",
      "1,042.5", "2 reels", "Still running", "Technician: signature and date",
      "Printed", users(:office).name, "Page 1 of 2" ].each { assert_includes text, _1 }
  end

  test "a finished log shows what was taken off stock and who finished it" do
    finish_cleanly(@run)
    @run.update_columns(finished_by_id: users(:floor).id)
    text = pdf_text(@run)
    assert_not_includes text, "IN PROGRESS"
    assert_includes text, "Used (kg)"
    assert_includes text, "1–2"
    assert_includes text, users(:floor).name
    assert_equal "despatch-#{@run.despatch_number}.pdf", ProductionLogPdf.new(@run).filename
  end

  test "a long reel sheet runs onto more pages" do
    add_reels(@run, *Array.new(60, 1_000))
    text = pdf_text(@run)
    assert_includes text, "62 reels"
    assert_includes text, "Page 3 of 3"
    assert_equal 2, text.scan("Running total (kg)").size, "the reel table's header repeats on the next page"
  end

  test "names that Helvetica can't print are transliterated" do
    @run.update!(technician_nights: "Łukasz Wójcik")
    assert_includes pdf_text(@run), "Lukasz Wójcik"
  end

  test "reel corrections and reading notes are printed for the record" do
    @run.reels.first.update!(weight_kg: "1,040", note: "Reweighed on the floor scale")
    @run.record_measurement(stage: "startup", item: "width", actual: "705", note: "Edge trim adjusted")
    text = pdf_text(@run)
    assert_includes text, "Reel 1 note: Reweighed on the floor scale"
    assert_includes text, "Edge trim adjusted"
    assert_includes text, "Tolerance"
    assert_not_includes text, "Passes"
  end
end
