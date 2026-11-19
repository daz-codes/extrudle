class PurchaseOrderLinesController < ApplicationController
  require_role :admin, :office
  before_action :set_purchase_order
  before_action :require_editable_order
  before_action :set_line, only: %i[ edit update destroy ]

  def create
    @line = @purchase_order.lines.build(line_params)

    if @line.save
      redirect_to @purchase_order, notice: "Added #{@line.material} to #{@purchase_order.number}."
    else
      @purchase_order.lines.reset
      render "purchase_orders/show", status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @line.update(line_params)
      redirect_to @purchase_order, notice: "Line for #{@line.material} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def destroy
    @line.destroy!
    redirect_to @purchase_order, notice: "Removed #{@line.material} from #{@purchase_order.number}.", status: :see_other
  end

  private
    def set_purchase_order
      @purchase_order = PurchaseOrder.find(params[:purchase_order_id])
    end

    def require_editable_order
      return if @purchase_order.editable?

      redirect_to @purchase_order, alert: "#{@purchase_order.number} is #{@purchase_order.status.humanize.downcase}. Take it back to draft to change it.", status: :see_other
    end

    def set_line
      @line = @purchase_order.lines.find(params[:id])
    end

    # quantity_unit is listed first so quantity is parsed in the chosen unit.
    def line_params
      params.expect(purchase_order_line: %i[ material_id quantity_unit quantity price_per_tonne ])
    end
end
