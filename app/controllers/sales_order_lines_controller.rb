class SalesOrderLinesController < ApplicationController
  require_role :admin, :office
  before_action :set_sales_order
  before_action :require_editable_order
  before_action :set_line, only: %i[ edit update destroy ]

  def create
    @line = @sales_order.lines.build(line_params)

    if @line.save
      redirect_to @sales_order, notice: "Added #{@line.product_spec} to #{@sales_order.number}."
    else
      @sales_order.lines.reset
      render "sales_orders/show", status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @line.update(line_params)
      redirect_to @sales_order, notice: "Line for #{@line.product_spec} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    if @line.destroy
      redirect_to @sales_order, notice: "Removed #{@line.product_spec} from #{@sales_order.number}.", status: :see_other
    else
      redirect_to @sales_order, alert: "#{@line.product_spec} is on the planner. Take it off the plan first.", status: :see_other
    end
  end

  private
    def set_sales_order
      @sales_order = SalesOrder.find(params[:sales_order_id])
    end

    def require_editable_order
      redirect_to @sales_order, alert: "This order can't be changed any more.", status: :see_other unless @sales_order.editable?
    end

    def set_line
      @line = @sales_order.lines.find(params[:id])
    end

    # quantity_unit is listed first so quantity is parsed in the chosen unit.
    def line_params
      params.expect(sales_order_line: %i[ product_spec_id quantity_unit quantity customer_batch_no price_per_tonne ])
    end
end
