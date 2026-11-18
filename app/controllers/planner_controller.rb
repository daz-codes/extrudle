class PlannerController < ApplicationController
  include PlannerBoard
  require_role :admin, :office

  def show
    @lines = Line.active.ordered
    line = @lines.detect { _1.name == params[:line].to_s.upcase } || @lines.first
    return redirect_to(lines_path, alert: "Add a line before planning.") unless line

    load_board(line, Schedule::Timeline.week_start_for(week_param))
  end

  # Printable plan, laid out like paper form 5.4.1.1 with calculated times.
  def print
    @lines = Line.active.ordered
    @lines = @lines.where(name: params[:line].to_s.upcase) if params[:line].present?
    @from = Time.current.beginning_of_day
    @plans = @lines.to_h do |line|
      all = line.schedule_blocks.ordered
        .includes(sales_order_line: [ :schedule_blocks, { sales_order: :customer }, { product_spec: :line_rates } ]).to_a
      [ line, { blocks: all.select { _1.ends_at > @from }, warnings: Schedule::Warnings.for_line(line, all) } ]
    end
    render layout: "print"
  end
end
