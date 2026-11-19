# Bags on the lines, bags waiting to be reconciled and the variance on bags
# that have been (PLAN.md §4).
class StockVariancesController < ApplicationController
  require_role :admin, :office

  def show
    @report = Stock::Variance.new
  end
end
