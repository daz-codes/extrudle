require "test_helper"

class ReelsControllerTest < ActionDispatch::IntegrationTest
  include ScheduleTestHelper

  setup do
    start = ProductionRun::Start.new(schedule_block: planned_job)
    assert start.save
    @run = start.run
    sign_in_as users(:floor)
  end

  test "the reels tab shows the next reel ready to fill in" do
    @run.reels.create!(weight_kg: "1,000", pallet_no: 1, initials: "DH")
    get production_run_reels_path(@run)
    assert_response :success
    assert_select "h2", /Reel\s+2/
    assert_select "input[name='reel[pallet_no]'][value='2']"
    assert_select "input[name='reel[initials]'][value='DH']"
    assert_select "[role=progressbar][aria-valuenow='10']"
  end

  test "adding a reel with Turbo replaces the panel" do
    post production_run_reels_path(@run), params: { reel: { weight_kg: "1,042.5", length_m: "5620", pallet_no: "1", initials: "dh" } },
         as: :turbo_stream
    assert_response :success
    assert_equal "text/vnd.turbo-stream.html", response.media_type
    assert_match "Reel 1 added: 1,042.5 kg.", response.body
    assert_match 'id="reels_panel"', response.body

    reel = @run.reels.sole
    assert_equal [ 1, 1_042_500, 5_620, 1, "DH", users(:floor) ], [ reel.reel_no, reel.weight_g, reel.length_m, reel.pallet_no, reel.initials, reel.user ]
  end

  test "a bad reel comes back with errors" do
    post production_run_reels_path(@run), params: { reel: { weight_kg: "" } }, as: :turbo_stream
    assert_response :unprocessable_content
    assert_match "Weight", response.body
    assert_equal 0, @run.reels.count
  end

  test "edit any reel, remove only the last" do
    first = @run.reels.create!(weight_kg: "1,000")
    last = @run.reels.create!(weight_kg: "1,000")

    patch production_run_reel_path(@run, first), params: { reel: { weight_kg: "995.5", note: "Reweighed" } }
    assert_redirected_to production_run_reels_path(@run)
    assert_equal 995_500, first.reload.weight_g

    delete production_run_reel_path(@run, first)
    assert_match "Only the last reel", flash[:alert]
    delete production_run_reel_path(@run, last)
    assert_equal [ first ], @run.reels.reload.to_a
  end

  test "finish from the end-of-run tab" do
    post production_run_finish_path(@run)
    assert_match "Not finished yet: enter at least one reel", flash[:alert]

    @run.reels.create!(weight_kg: "1,050")
    post production_run_material_loads_path(@run), params: { material_load: { lot_code: lots(:jade_opening).code } }
    %w[ width thickness ].zip(%w[ 700 250 ]).each do |item, actual|
      post production_run_checks_path(@run), params: { stage: "end_of_run", item:, actual: }
      assert_redirected_to production_run_finish_path(@run, anchor: "end_of_run")
    end
    ProductionRun::Checklist.items("line_clearance").each_key do |item|
      post production_run_checks_path(@run), params: { stage: "line_clearance", item:, passed: "true" }
    end

    get production_run_finish_path(@run)
    assert_select "button:not([disabled])", text: "Finish log"

    post production_run_finish_path(@run)
    assert_redirected_to production_run_finish_path(@run)
    assert_equal "Despatch 1 is finished: 1 reel, 1,050 kg.", flash[:notice]
    assert @run.reload.finished?
    assert_equal(-1_050_000, @run.consumptions.sole.quantity_g)

    post production_run_reels_path(@run), params: { reel: { weight_kg: "900" } }
    assert_match "is finished", flash[:alert]
  end

  # The other terminal's reel was saved after this one was numbered: the
  # reel passes validation, then goes in with the stale number, so only the
  # unique index can catch it.
  module SimulateRace
    mattr_accessor :stale_reel_no

    def valid?(...)
      super.tap { |valid| self.reel_no = SimulateRace.stale_reel_no if valid && SimulateRace.stale_reel_no && new_record? }
    ensure
      SimulateRace.stale_reel_no = nil if valid_stale_used?
    end

    private
      def valid_stale_used? = new_record? && reel_no == SimulateRace.stale_reel_no
  end
  Reel.prepend(SimulateRace)

  test "two reels added at the same moment both get a number" do
    @run.reels.create!(weight_kg: "1,000")
    @run.reels.create!(weight_kg: "1,050") # the other terminal's reel 2
    SimulateRace.stale_reel_no = 2

    post production_run_reels_path(@run), params: { reel: { weight_kg: "1,100" } }, as: :turbo_stream
    assert_response :success
    assert_equal [ [ 1, 1_000_000 ], [ 2, 1_050_000 ], [ 3, 1_100_000 ] ], @run.reels.reload.map { [ _1.reel_no, _1.weight_g ] }
    assert_match "Reel 3 added", response.body
  ensure
    SimulateRace.stale_reel_no = nil
  end
end
