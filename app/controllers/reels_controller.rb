# Reel entry: page 2 of the production log. Built for speed on a touch screen:
# each reel is added with Turbo, and the form comes back with the next reel
# number, pallet and initials filled in and the weight box focused.
class ReelsController < ApplicationController
  include FloorOrOfficeLayout
  before_action :set_run
  before_action :require_running, except: :index
  before_action :set_reel, only: %i[ edit update destroy ]

  def index
    @reel = @run.build_next_reel
  end

  def create
    @reel = Reel.new(production_run_id: @run.id, user: Current.user, **reel_params)

    if save_with_next_number(@reel)
      @run.reels.reset
      flash.now[:notice] = "Reel #{@reel.reel_no} added: #{Weight.format_kg(@reel.weight_g)}."
      @reel = @run.build_next_reel
      respond_with_panel
    else
      respond_with_panel(status: :unprocessable_content)
    end
  end

  def edit
  end

  def update
    if @reel.update(reel_params.except(:reel_no))
      redirect_to production_run_reels_path(@run), notice: "Reel #{@reel.reel_no} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Only the last reel can be removed, so the numbers stay in sequence.
  # Working assumption, see PLAN.md §11 Q43.
  def destroy
    if @reel.reel_no == @run.reels.maximum(:reel_no) && @reel.destroy
      redirect_to production_run_reels_path(@run), notice: "Reel #{@reel.reel_no} was removed.", status: :see_other
    else
      redirect_to production_run_reels_path(@run), alert: "Only the last reel can be removed. Correct other reels with Edit.", status: :see_other
    end
  end

  private
    def set_run
      @run = ProductionRun.includes(:line, :product_spec, reels: :user, sales_order_line: { sales_order: :customer }).find(params[:production_run_id])
    end

    def set_reel
      @reel = @run.reels.find(params[:id])
    end

    def require_running
      return if @run.running?

      redirect_to production_run_reels_path(@run), alert: "Despatch #{@run.despatch_number} is finished, so its reels can't change.", status: :see_other
    end

    def reel_params
      params.expect(reel: %i[ weight_kg length_m pallet_no initials note ])
    end

    # Two terminals can add a reel at the same moment and both pick the same
    # number. The unique index catches it; take the next number and try again.
    def save_with_next_number(reel, attempts: 3)
      reel.save
    rescue ActiveRecord::RecordNotUnique
      raise if (attempts -= 1).zero?

      reel.reel_no = ProductionRun.find(@run.id).next_reel_no
      retry
    end

    def respond_with_panel(status: :ok)
      respond_to do |format|
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace("reels_panel", partial: "reels/panel", locals: { run: @run, reel: @reel }),
            turbo_stream.update("flash", partial: "shared/flash")
          ], status:
        end
        format.html do
          if status == :ok
            redirect_to production_run_reels_path(@run), notice: flash.now[:notice], alert: flash.now[:alert]
          else
            render :index, status:
          end
        end
      end
    end
end
