require "application_system_test_case"

class ReelsTest < ApplicationSystemTestCase
  include ScheduleTestHelper
  include MaterialTestHelper

  test "a technician enters reels quickly and finishes the log" do
    start = ProductionRun::Start.new(schedule_block: planned_job, despatch_number: 731)
    assert start.save
    sign_in users(:floor)

    within("#production_line_#{lines(:d1).id}") { click_on "Enter reels" }
    wait_for_turbo

    fill_in "Weight", with: "1042.5"
    fill_in "Initials", with: "dh"
    click_on "Add reel"
    assert_text "Reel 1 added: 1,042.5 kg."
    assert_selector "h2", text: "Reel 2"

    # The weight box is focused again and the initials carried over.
    assert_equal "reel_weight_kg", page.evaluate_script("document.activeElement.id")
    assert_field "Initials", with: "DH"
    fill_in "Weight", with: "1061"
    click_on "Add reel"
    assert_text "Reel 2 added"
    assert_text "2.1035 t"
    assert_text "21%"

    # A scanner types the lot code and presses Enter.
    jade = bag(materials(:jade), kg: 5_000)
    click_on "Materials (0)"
    assert_selector "h2", text: "Load a bag"
    assert_equal "material_load_lot_code", page.evaluate_script("document.activeElement.id")
    find_field("Lot code").send_keys(jade.code, :enter)
    assert_text "#{jade.code} (JADE) is on Virgin Main-Ex from reel 3."
    within("#feed_virgin_mainex") { assert_text "Reels 3 onwards" }
    assert_text "Material used so far (estimate)"

    click_on "End of run and finish"
    fill_in "Width actual", with: "701"
    click_on "Record width"
    assert_text "Width 701 mm: in tolerance."
    fill_in "Thickness actual", with: ".249"
    click_on "Record thickness"
    # Each answer reloads the page: wait for it before the next click.
    [ "Materials cleared from the line", "Log, labels and documents removed", "Line cleared for the next micron" ].each do |check|
      click_on "#{check}: yes"
      assert_text "#{check}: yes."
    end
    assert_text "All done"

    accept_confirm { click_on "Finish log" }
    assert_text "Despatch 731 is finished: 2 reels, 2,103.5 kg."
    assert_no_button "Finish log"
    within("section[aria-labelledby=use-heading]") { assert_text "2,103.5 kg" }
    assert_equal 5_000_000 - 2_103_500, jade.reload.quantity_g
  end
end
