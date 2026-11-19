# Loads everything the planner board shows for one line and week, so the page
# and every Turbo Stream update render the same thing.
module PlannerBoard
  extend ActiveSupport::Concern

  included do
    helper_method :planner_path_for
  end

  private
    # plan: the plan shown (Schedule::Plan). While a draft exists the live plan
    # is shown read-only (§11 Q52).
    def load_board(line, week_start, plan = Schedule::Plan.current)
      @line = line
      @week_start = week_start
      @plan = Schedule::Plan.new(plan.draft).preload_planned!
      @draft = PlanDraft.current
      @read_only = @plan.live? && @draft.present?
      @queue_start = @plan.queue_start(line)
      @blocks = @plan.blocks_for(line).ordered
        .includes(:source_block, sales_order_line: [ { sales_order: :customer }, { product_spec: :line_rates } ]).to_a
      @queue_empty = @blocks.none? { !_1.locked? }
      @warnings = Schedule::Warnings.for_line(line, @blocks, plan: @plan)
      @timeline = Schedule::Timeline.new(@blocks, week_start: week_start)
      @unplanned = unplanned_order_lines
    end

    # Order lines still to plan on the plan shown, most pressing first.
    def unplanned_order_lines
      SalesOrderLine.joins(:sales_order).merge(SalesOrder.active)
        .includes({ sales_order: :customer }, { product_spec: :line_rates })
        .select { @plan.unplanned_g(_1).positive? }
        .sort_by { [ _1.sales_order.required_on, _1.sales_order.urgent? ? 0 : 1, _1.sales_order.number, _1.id ] }
    end

    def week_param
      Date.iso8601(params[:week].to_s)
    rescue Date::Error
      Date.current
    end

    def planner_path_for(line, week_start, plan: nil)
      planner_path(line: line.name, week: week_start.iso8601, plan:)
    end

    def render_board(status: :ok)
      load_board(@line, Schedule::Timeline.week_start_for(week_param), @plan || Schedule::Plan.current)
      render turbo_stream: [
        turbo_stream.replace("planner_board", partial: "planner/board"),
        turbo_stream.update("flash", partial: "shared/flash")
      ], status: status
    end
end
