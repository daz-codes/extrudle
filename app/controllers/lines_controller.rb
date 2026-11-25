class LinesController < ApplicationController
  include MasterData
  before_action :set_line, only: %i[ edit update ]

  def index
    @lines = Line.ordered.includes(:line_rates)
  end

  def new
    @line = Line.new(position: (Line.maximum(:position) || 0) + 1)
  end

  def create
    @line = Line.new(line_params)

    if @line.save
      redirect_to lines_path, notice: "Line #{@line.name} was added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @line.update(line_params)
      redirect_to lines_path, notice: "Line #{@line.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_line
      @line = Line.find(params[:id])
    end

    def line_params
      params.expect(line: %i[ name machine_no default_changeover_minutes default_kg_per_hour position active ])
    end
end
