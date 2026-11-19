class LotAdjustmentsController < ApplicationController
  require_role :admin, :office
  before_action :set_lot

  def new
    @adjustment = Stock::Adjustment.new(lot: @lot)
  end

  def create
    @adjustment = Stock::Adjustment.new(lot: @lot, **params.expect(stock_adjustment: %i[ counted_kg reason ]).to_h.symbolize_keys)
    @adjustment.user = Current.user

    if @adjustment.save
      redirect_to @lot, notice: "#{@lot.code} now weighs #{Weight.format_kg(@adjustment.counted_g)}."
    else
      render :new, status: :unprocessable_content
    end
  end

  private
    def set_lot
      @lot = Lot.with_quantity.includes(:material).find(params[:lot_id])
    end
end
