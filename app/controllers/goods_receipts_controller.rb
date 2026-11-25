# Goods in against a purchase order, in the office or on the floor (Slice 12;
# operators can receive deliveries, PLAN.md §11 Q31, Q81). Floor users get the
# floor layout and go back to the floor's delivery page.
class GoodsReceiptsController < ApplicationController
  include FloorOrOfficeLayout
  before_action :set_purchase_order
  before_action :require_receivable

  def new
    line = @purchase_order.lines.find_by(id: params[:line]) || @purchase_order.lines.find { !_1.fully_received? } || @purchase_order.lines.first
    @receipt = Stock::Receipt.new(purchase_order_line: line, quantity_unit: line&.quantity_unit || "kg")
  end

  def create
    line = @purchase_order.lines.find(params.dig(:receipt, :purchase_order_line_id))
    @receipt = Stock::Receipt.new(purchase_order_line: line, **receipt_params)
    @receipt.user = Current.user

    if @receipt.save
      lots = @receipt.lots
      notice = "Received #{helpers.pluralize(lots.size, "bag")} of #{line.material.name} as #{lot_range(lots)}. Print their labels below."
      to = Current.user.floor? ? floor_delivery_path(@purchase_order) : lots_path(po_line: line.id, received_on: @receipt.received_on)
      redirect_to to, notice:
    else
      render :new, status: :unprocessable_content
    end
  end

  private
    def set_purchase_order
      @purchase_order = PurchaseOrder.includes(lines: %i[ material lots ]).find(params[:purchase_order_id])
    end

    def require_receivable
      return if @purchase_order.receivable?

      redirect_to back_path, alert: "#{@purchase_order.number} is #{@purchase_order.status.humanize.downcase}, so goods can't be received against it.", status: :see_other
    end

    # quantity_unit is listed first so quantity is parsed in the chosen unit.
    def receipt_params
      params.expect(receipt: %i[ received_on bags first_bag_no supplier_lot_ref delivery_ref location quantity_unit quantity notes confirm_large_delivery ]).to_h.symbolize_keys
    end

    def back_path
      Current.user.floor? ? floor_delivery_path(@purchase_order) : @purchase_order
    end
    helper_method :back_path

    def lot_range(lots)
      lots.one? ? lots.first.code : "#{lots.first.code} to #{lots.last.code}"
    end
end
