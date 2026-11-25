# Goods in on the floor (Slice 12): the deliveries still to come in, and one
# purchase order with the bags received against it today and their labels.
# Operators see weights, not prices (§11 Q81, Q82).
class Floor::DeliveriesController < ApplicationController
  layout "floor"

  def index
    @purchase_orders = PurchaseOrder.outstanding.by_expected_date.includes(:supplier, lines: %i[ material lots ])
  end

  def show
    @purchase_order = PurchaseOrder.includes(:supplier, lines: %i[ material lots ]).find(params[:id])
    @lots = Lot.with_quantity.includes(:material).by_code
      .where(purchase_order_line: @purchase_order.lines, created_at: Time.current.all_day)
  end
end
