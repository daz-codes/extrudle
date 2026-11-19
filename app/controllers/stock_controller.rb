# Stock on hand by category and material, split by location, with what's still on order.
class StockController < ApplicationController
  require_role :admin, :office

  def show
    @report = Stock::OnHand.new
  end
end
