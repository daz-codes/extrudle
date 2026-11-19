# The materials section of the log: which bag went on which feed, from which
# reel. Built for the floor screen and a scanner: the lot code box is focused,
# and a scan (the code plus Enter) adds the bag on its usual feed.
class MaterialLoadsController < ApplicationController
  include FloorOrOfficeLayout
  before_action :set_run
  before_action :require_running, except: :index

  def index
    @loading = ProductionRun::LoadMaterial.new(run: @run)
  end

  def create
    @loading = ProductionRun::LoadMaterial.new(run: @run, **load_params)
    @loading.user = Current.user

    if @loading.save
      load = @loading.load
      redirect_to production_run_material_loads_path(@run), notice: "#{load.lot.code} (#{load.lot.material.name}) is on #{load.feed_label} from reel #{load.from_reel_no}."
    else
      render :index, status: :unprocessable_content
    end
  end

  # A bag recorded by mistake. Only the latest bag on a feed can be removed,
  # so the reel ranges stay right. It doesn't undo marking the bag before empty.
  def destroy
    load = @run.material_loads.find(params[:id])
    if @run.current_loads[load.feed] == load && load.destroy
      redirect_to production_run_material_loads_path(@run), notice: "#{load.lot.code} was taken off #{load.feed_label}.", status: :see_other
    else
      redirect_to production_run_material_loads_path(@run), alert: "Only the latest bag on a feed can be removed.", status: :see_other
    end
  end

  # The bag on a feed ran out (and nothing else went on yet).
  def empty
    load = @run.material_loads.find(params[:id])
    Stock::Reconciliation.mark_empty(load.lot, user: Current.user)
    redirect_to production_run_material_loads_path(@run), notice: "#{load.lot.code} was marked empty.", status: :see_other
  end

  private
    def set_run
      @run = ProductionRun.includes(:line, :product_spec, :reels, material_loads: [ :user, { lot: { material: :material_category } } ],
                                    sales_order_line: { sales_order: :customer }).find(params[:production_run_id])
    end

    def require_running
      return if @run.running?

      redirect_to production_run_material_loads_path(@run), alert: "Despatch #{@run.despatch_number} is finished, so its materials can't change.", status: :see_other
    end

    def load_params
      params.expect(material_load: %i[ lot_code feed from_reel_no initials note previous_empty ]).to_h.symbolize_keys
    end
end
