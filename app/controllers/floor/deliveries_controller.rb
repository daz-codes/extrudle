# Goods in on the floor (Slice 12): the deliveries still to come in, and one
# purchase order with the bags received against it today and their labels.
# Operators see weights, not prices (§11 Q81, Q82).
class Floor::DeliveriesController < ApplicationController
  layout "floor"

  def index
    @purchase_orders = PurchaseOrder.outstanding.by_expected_date.includes(:supplier, lines: %i[ material lots ])
  end

  # Sent and part-received orders, and received ones so the last delivery's
  # labels can still be printed. Drafts and cancelled orders aren't deliveries.
  SHOWN_STATUSES = (PurchaseOrder::OUTSTANDING_STATUSES + %w[ received ]).freeze

  def show
    @purchase_order = PurchaseOrder.includes(:supplier, lines: %i[ material lots ]).find(params[:id])
    unless SHOWN_STATUSES.include?(@purchase_order.status)
      redirect_to floor_deliveries_path, alert: "#{@purchase_order.number} is #{@purchase_order.status.humanize.downcase}, so it isn't a delivery to receive."
      return
    end

    @lots = Lot.with_quantity.includes(:material).by_code
      .where(purchase_order_line: @purchase_order.lines, created_at: Time.current.all_day)
  end
end
