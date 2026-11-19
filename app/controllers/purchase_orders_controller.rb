class PurchaseOrdersController < ApplicationController
  require_role :admin, :office
  before_action :set_purchase_order, except: %i[ index new create ]

  STATUS_FILTERS = { "active" => "Open", "all" => "All" }.merge(PurchaseOrder.statuses.keys.index_with(&:humanize)).freeze

  def index
    @status = STATUS_FILTERS.key?(params[:status]) ? params[:status] : "active"
    @query = params[:q].to_s.strip.presence
    @supplier = Supplier.find_by(id: params[:supplier]) if params[:supplier].present?

    orders = PurchaseOrder.includes(:supplier, lines: :material).search(@query)
    orders = orders.where(supplier: @supplier) if @supplier
    @purchase_orders = case @status
    when "active" then orders.active
    when "all" then orders
    else orders.where(status: @status)
    end.by_expected_date
  end

  def show
    respond_to do |format|
      format.html { @line = PurchaseOrderLine.new if @purchase_order.editable? } # not linked, so it stays out of @purchase_order.lines
      format.pdf do
        send_data PurchaseOrderPdf.new(@purchase_order).render, type: "application/pdf", disposition: "inline",
                  filename: "#{@purchase_order.number}#{"-draft" if @purchase_order.draft?}.pdf"
      end
    end
  end

  def new
    @purchase_order = PurchaseOrder.new(supplier_id: params[:supplier], expected_on: 2.weeks.from_now.to_date)
  end

  def create
    @purchase_order = PurchaseOrder.new(purchase_order_params)

    if @purchase_order.save_with_number
      redirect_to @purchase_order, notice: "#{@purchase_order.number} was created. Add its lines below."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
    redirect_to @purchase_order, alert: not_editable_message unless @purchase_order.editable?
  end

  def update
    return redirect_to(@purchase_order, alert: not_editable_message) unless @purchase_order.editable?

    if @purchase_order.update(purchase_order_params)
      redirect_to @purchase_order, notice: "#{@purchase_order.number} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  def mark_sent
    transition(:mark_sent!, "#{@purchase_order.number} is marked as sent. Download the PDF to email it.")
  end

  def back_to_draft
    transition(:back_to_draft!, "#{@purchase_order.number} is back to draft. Send it again once it's changed.")
  end

  def cancel
    transition(:cancel!, "#{@purchase_order.number} was cancelled.")
  end

  def close_short
    transition(:close_short!, "#{@purchase_order.number} is closed. Nothing more is expected against it.")
  end

  def reopen
    transition(:reopen!, "#{@purchase_order.number} was reopened as a draft.")
  end

  private
    def set_purchase_order
      @purchase_order = PurchaseOrder.includes(lines: [ :lots, { material: %i[ material_category supplier ] } ]).find(params[:id])
    end

    def purchase_order_params
      permitted = %i[ expected_on supplier_ref incoterm notes ]
      permitted += %i[ supplier_id currency ] if @purchase_order.nil? || @purchase_order.lines.none?
      params.expect(purchase_order: permitted)
    end

    def transition(action, notice)
      @purchase_order.public_send(action)
      redirect_to @purchase_order, notice:, status: :see_other
    rescue ArgumentError => e
      redirect_to @purchase_order, alert: e.message.upcase_first, status: :see_other
    end

    def not_editable_message
      "#{@purchase_order.number} is #{@purchase_order.status.humanize.downcase}, so it can't be changed."
    end
end
