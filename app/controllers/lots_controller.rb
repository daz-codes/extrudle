class LotsController < ApplicationController
  require_role :admin, :office
  before_action :set_lot, only: %i[ show move ]

  def index
    @lots = filtered_lots.includes(:material, purchase_order_line: :purchase_order).order(received_on: :desc, code: :desc)
  end

  # An A4 sheet of QR labels for the lots in the current filter (or ids[]).
  def labels
    @lots = filtered_lots.includes(:material, purchase_order_line: { purchase_order: :supplier }).by_code
    render layout: "print"
  end

  def show
    @movements = @lot.movements.includes(:user, :production_run).reverse
    @loads = @lot.material_loads.includes(production_run: :line)
  end

  # Stock without a purchase order: opening stock at go-live and in-house
  # regrind. Working assumption, see PLAN.md §11 Q32.
  def new
    @receipt = Stock::Receipt.new(material_id: params[:material])
  end

  def create
    @receipt = Stock::Receipt.new(**receipt_params)
    @receipt.user = Current.user

    if @receipt.save
      redirect_to lots_path(material: @receipt.material_id, received_on: @receipt.received_on, unlinked: 1),
                  notice: "Added #{helpers.pluralize(@receipt.lots.size, "lot")} of #{@receipt.material.name}. Print their labels below."
    else
      render :new, status: :unprocessable_content
    end
  end

  def move
    moved = Stock::Transfer.call(@lot, to: params[:location], user: Current.user, note: params[:note])
    notice = moved.any? ? "#{@lot.code} moved to #{@lot.reload.location_label.downcase}." : "#{@lot.code} is already there."
    redirect_to @lot, notice:, status: :see_other
  rescue Stock::Transfer::Error => e
    redirect_to @lot, alert: e.message, status: :see_other
  end

  private
    def set_lot
      @lot = Lot.with_quantity.includes(:material, purchase_order_line: { purchase_order: :supplier }).find(params[:id])
    end

    # Shared by the list and the label sheet, so "Print labels" prints what's listed.
    def filtered_lots
      @query = params[:q].to_s.strip.presence
      @material = Material.find_by(id: params[:material]) if params[:material].present?
      @location = params[:location] if Lot::LOCATIONS.key?(params[:location])
      @po_line = PurchaseOrderLine.find_by(id: params[:po_line]) if params[:po_line].present?
      @received_on = params[:received_on].presence&.then { Date.parse(_1) rescue nil }
      @include_empty = params[:empty] == "1"

      lots = Lot.with_quantity.search(@query)
      lots = lots.where(id: Array(params[:ids])) if params[:ids].present?
      lots = lots.where(material: @material) if @material
      lots = lots.where(location: @location) if @location
      lots = lots.where(purchase_order_line: @po_line) if @po_line
      lots = lots.where(purchase_order_line: nil) if params[:unlinked] == "1"
      lots = lots.where(received_on: @received_on) if @received_on
      lots = lots.in_stock unless @include_empty || params[:ids].present?
      lots
    end

    def receipt_params
      params.expect(receipt: %i[ material_id received_on bags first_bag_no supplier_lot_ref delivery_ref location quantity_unit quantity notes ]).to_h.symbolize_keys
    end
end
