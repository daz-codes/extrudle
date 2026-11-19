require "test_helper"

class MaterialLoadsControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper
  include MaterialTestHelper

  setup do
    @run = start_run
    sign_in_as users(:floor)
  end

  test "the materials tab shows each feed and the load form" do
    load_bag(@run, lots(:jade_opening))
    get production_run_material_loads_path(@run)
    assert_response :success
    assert_select "#feed_virgin_mainex", /#{lots(:jade_opening).code}/
    assert_select "#feed_pcw .badge", "No bag recorded"
    assert_select "input[name='material_load[lot_code]'][data-controller=autofocus]"
    assert_select "datalist#loadable_lots option[value='#{lots(:regrind_bag).code}']"
    assert_select "a.tab[aria-current=page]", "Materials (1)"
  end

  test "a floor user loads a bag by its code" do
    post production_run_material_loads_path(@run), params: { material_load: { lot_code: lots(:regrind_bag).code.downcase, initials: "dh" } }
    assert_redirected_to production_run_material_loads_path(@run)
    assert_equal "#{lots(:regrind_bag).code} (Regrind chip) is on Regrind from reel 1.", flash[:notice]
    load = @run.material_loads.sole
    assert_equal [ "regrind", "DH", users(:floor) ], [ load.feed, load.initials, load.user ]
  end

  test "an unknown code shows the form again with the error" do
    post production_run_material_loads_path(@run), params: { material_load: { lot_code: "L-1999-000009" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /L-1999-000009 isn't a lot code we know/
    assert_select "input[name='material_load[lot_code]'][value='L-1999-000009']"
  end

  test "only the latest bag on a feed can be removed" do
    first = load_bag(@run, lots(:jade_opening))
    second = load_bag(@run, bag(materials(:jade)), previous_empty: false)

    delete production_run_material_load_path(@run, first)
    assert_match "Only the latest bag", flash[:alert]
    delete production_run_material_load_path(@run, second)
    assert_equal [ first ], @run.material_loads.reload.to_a
  end

  test "a bag can be marked empty from the log" do
    load = load_bag(@run, lots(:jade_opening))
    patch empty_production_run_material_load_path(@run, load)
    assert_redirected_to production_run_material_loads_path(@run)
    assert lots(:jade_opening).reload.emptied?
  end

  test "a finished log's materials can't change" do
    load_bag(@run, lots(:jade_opening))
    add_reels(@run, 500)
    finish_cleanly(@run)

    get production_run_material_loads_path(@run)
    assert_select "h2", "Material used"
    assert_select "td", "500 kg"
    assert_select "input[name='material_load[lot_code]']", count: 0

    post production_run_material_loads_path(@run), params: { material_load: { lot_code: lots(:regrind_bag).code } }
    assert_match "is finished", flash[:alert]
  end
end
