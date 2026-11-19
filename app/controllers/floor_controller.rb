class FloorController < ApplicationController
  layout "floor"

  def show
    @board = ProductionRun::Board.new
  end
end
