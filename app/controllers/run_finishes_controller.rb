# The end-of-run tab: end readings, line clearance and finishing the log.
class RunFinishesController < ApplicationController
  include FloorOrOfficeLayout
  before_action :set_run

  def show
  end

  def create
    @run.finish!(user: Current.user)
    redirect_to production_run_finish_path(@run), notice: "Despatch #{@run.despatch_number} is finished: #{helpers.pluralize(@run.reels.size, "reel")}, #{Weight.format_kg(@run.total_g)}.", status: :see_other
  rescue ProductionRun::NotFinishable => e
    redirect_to production_run_finish_path(@run), alert: "Not finished yet: #{e.message.downcase_first}.", status: :see_other
  end

  private
    def set_run
      @run = ProductionRun.includes(:line, :product_spec, :reels, checks: :user, sales_order_line: { sales_order: :customer }).find(params[:production_run_id])
    end
end
