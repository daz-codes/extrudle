require "application_system_test_case"

class ReelsTest < ApplicationSystemTestCase
  include ScheduleTestHelper

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

    click_on "End of run and finish"
    fill_in "Width actual", with: "701"
    click_on "Record width"
    assert_text "Width 701 mm: in tolerance."
    fill_in "Thickness actual", with: ".249"
    click_on "Record thickness"
    click_on "Materials cleared from the line: yes"
    click_on "Log, labels and documents removed: yes"
    click_on "Line cleared for the next micron: yes"
    assert_text "All done"

    accept_confirm { click_on "Finish log" }
    assert_text "Despatch 731 is finished: 2 reels, 2,103.5 kg."
    assert_no_button "Finish log"
  end
end
