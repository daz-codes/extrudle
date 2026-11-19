require "application_system_test_case"

class ProductionRunsTest < ApplicationSystemTestCase
  include ScheduleTestHelper

  test "a technician starts a log on the floor and does the checks" do
    planned_job
    sign_in users(:floor)

    within("#production_line_#{lines(:d1).id}") { click_on "Start log" }
    wait_for_turbo
    fill_in "Despatch number", with: "731"
    fill_in "Technician (days)", with: "Dave Hirst"
    click_on "Start log"

    assert_text "Despatch 731 started"
    click_on "Previous documents and labels removed: yes"
    assert_text "Previous documents and labels removed: yes."
    click_on "Previous product cleared from the line: yes"
    assert_text "All done"

    fill_in "Thickness actual", with: ".252"
    click_on "Record thickness"
    assert_text "Thickness 252 µm: in tolerance."
    within("#measure_thickness") { assert_text "252 µm (+2)" }

    fill_in "Width actual", with: "705"
    click_on "Record width"
    within("#measure_width") { assert_text "Fail" }
  end
end
