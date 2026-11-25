class SalesOrdersController < ApplicationController
  require_role :admin, :office
  before_action :set_sales_order, only: %i[ show edit update cancel reopen mark_dispatched ]

  STATUS_FILTERS = { "active" => "Active", "all" => "All" }.merge(SalesOrder.statuses.keys.index_with(&:humanize)).freeze

  def index
    @status = STATUS_FILTERS.key?(params[:status]) ? params[:status] : "active"
    @window = SalesOrder::WINDOWS.key?(params[:window]) ? params[:window] : nil
    @query = params[:q].to_s.strip.presence

    orders = SalesOrder.includes(:customer, lines: :product_spec).search(@query)
    orders = case @status
    when "active" then orders.active
    when "all" then orders
    else orders.where(status: @status)
    end
    @window_counts = orders.window_counts
    @sales_orders = orders.in_window(@window).by_required_date
  end

  def show
    @line = SalesOrderLine.new if @sales_order.editable? # not linked, so it stays out of @sales_order.lines
  end

  def new
    @sales_order = SalesOrder.new(customer_id: params[:customer], required_on: 2.weeks.from_now.to_date)
  end

  def create
    @sales_order = SalesOrder.new(sales_order_params)

    if @sales_order.save_with_number
      redirect_to @sales_order, notice: "Order #{@sales_order.number} was created. Add its lines below."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    redirect_to @sales_order, alert: "This order can't be changed any more." unless @sales_order.editable?
  end

  def update
    return redirect_to(@sales_order, alert: "This order can't be changed any more.") unless @sales_order.editable?

    if @sales_order.update(sales_order_params)
      redirect_to @sales_order, notice: "Order #{@sales_order.number} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def cancel
    @sales_order.cancel!
    redirect_to @sales_order, notice: "Order #{@sales_order.number} was cancelled.", status: :see_other
  rescue ArgumentError => e
    redirect_to @sales_order, alert: e.message.capitalize, status: :see_other
  end

  # Closes an order that went out short, by hand (PLAN.md §11 Q66).
  def mark_dispatched
    @sales_order.mark_dispatched!
    redirect_to @sales_order, notice: "Order #{@sales_order.number} is dispatched.", status: :see_other
  rescue ArgumentError => e
    redirect_to @sales_order, alert: e.message, status: :see_other
  end

  def reopen
    @sales_order.reopen!
    redirect_to @sales_order, notice: "Order #{@sales_order.number} was reopened.", status: :see_other
  rescue ArgumentError => e
    redirect_to @sales_order, alert: e.message.capitalize, status: :see_other
  end

  private
    def set_sales_order
      @sales_order = SalesOrder.find(params[:id])
    end

    def sales_order_params
      params.expect(sales_order: %i[ customer_id customer_po_ref required_on required_week delivery_site urgent notes ])
    end
end
