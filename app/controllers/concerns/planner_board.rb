# Loads everything the planner board shows for one line and week, so the page
# and every Turbo Stream update render the same thing.
module PlannerBoard
  extend ActiveSupport::Concern

  included do
    helper_method :planner_path_for
  end

  private
    def load_board(line, week_start)
      @line = line
      @week_start = week_start
      @blocks = line.schedule_blocks.ordered
        .includes(sales_order_line: [ :schedule_blocks, { sales_order: :customer }, { product_spec: :line_rates } ]).to_a
      @warnings = Schedule::Warnings.for_line(line, @blocks)
      @timeline = Schedule::Timeline.new(@blocks, week_start: week_start)
      @unplanned = unplanned_order_lines
    end

    # Order lines still to plan, most pressing first.
    def unplanned_order_lines
      SalesOrderLine.joins(:sales_order).merge(SalesOrder.where(status: SalesOrder::EDITABLE_STATUSES))
        .includes(:schedule_blocks, { sales_order: :customer }, { product_spec: :line_rates })
        .select { _1.unplanned_g.positive? }
        .sort_by { [ _1.sales_order.required_on, _1.sales_order.urgent? ? 0 : 1, _1.sales_order.number, _1.id ] }
    end

    def week_param
      Date.iso8601(params[:week].to_s)
    rescue Date::Error
      Date.current
    end

    def planner_path_for(line, week_start)
      planner_path(line: line.name, week: week_start.iso8601)
    end

    def render_board(status: :ok)
      load_board(@line, Schedule::Timeline.week_start_for(week_param))
      render turbo_stream: [
        turbo_stream.replace("planner_board", partial: "planner/board"),
        turbo_stream.update("flash", partial: "shared/flash")
      ], status: status
    end
end
