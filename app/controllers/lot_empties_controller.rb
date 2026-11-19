# Marking a bag empty from the office (the floor does it from the log), and
# undoing it until the bag has been reconciled.
class LotEmptiesController < ApplicationController
  require_role :admin, :office
  before_action :set_lot

  def create
    Stock::Reconciliation.mark_empty(@lot, user: Current.user)
    redirect_to @lot, notice: "#{@lot.code} was marked empty.", status: :see_other
  rescue ArgumentError => e
    redirect_to @lot, alert: e.message, status: :see_other
  end

  def destroy
    Stock::Reconciliation.unmark_empty(@lot)
    redirect_to @lot, notice: "#{@lot.code} is no longer marked empty.", status: :see_other
  rescue ArgumentError => e
    redirect_to @lot, alert: e.message, status: :see_other
  end

  private
    def set_lot
      @lot = Lot.find(params[:lot_id])
    end
end
