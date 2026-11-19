# Delivery notes: pick finished pallets for an order, print the note, mark it
# dispatched. Only drafts can change; a dispatched note can go back to draft
# until it's been exported to Sage.
class DeliveryNotesController < ApplicationController
  require_role :admin, :office
  before_action :set_note, except: %i[ index new create ]
  before_action :require_draft, only: %i[ edit update destroy ]

  def index
    redirect_to dispatch_path
  end

  def show
    respond_to do |format|
      format.html
      format.pdf do
        send_data DeliveryNotePdf.new(@note).render, type: "application/pdf", disposition: "inline",
                  filename: "#{@note.number}#{"-draft" if @note.draft?}.pdf"
      end
    end
  end

  def new
    @order = SalesOrder.find(params[:order])
    @note = @order.delivery_notes.build(delivery_address: @order.customer.address)
    @pallets = @order.pallets_to_dispatch
    @selected = @pallets.map(&:key)
  end

  def create
    @order = SalesOrder.find(params.dig(:delivery_note, :sales_order_id))
    @note = @order.delivery_notes.build(note_params)
    @pallets = @order.pallets_to_dispatch
    @selected = Array(params[:pallets])
    keys = chosen_keys(@pallets)

    if keys.empty?
      @note.errors.add(:base, "Choose at least one pallet")
      return render(:new, status: :unprocessable_content)
    end

    DeliveryNote.transaction do
      @note.save_with_number || raise(ActiveRecord::RecordInvalid, @note)
      @note.set_pallets!(keys)
    end
    redirect_to @note, notice: "Delivery note #{@note.number} created. Print it, then mark it dispatched when the lorry leaves."
  rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique
    @note = @order.delivery_notes.build(note_params).tap { _1.errors.add(:base, "Those pallets couldn't be saved. One may have just gone on another note.") }
    @pallets = @order.pallets_to_dispatch
    render :new, status: :unprocessable_content
  end

  def edit
    @order = @note.sales_order
    @pallets = (@note.pallets + @order.pallets_to_dispatch).uniq
    @selected = @note.pallets.map(&:key)
  end

  def update
    @order = @note.sales_order
    @pallets = (@note.pallets + @order.pallets_to_dispatch).uniq
    @selected = Array(params[:pallets])
    keys = chosen_keys(@pallets)
    @note.assign_attributes(note_params)
    @note.errors.add(:base, "Choose at least one pallet") if keys.empty?
    return render(:edit, status: :unprocessable_content) if @note.errors.any? || !@note.valid?

    DeliveryNote.transaction do
      @note.save!
      @note.set_pallets!(keys)
    end
    redirect_to @note, notice: "#{@note.number} was updated."
  end

  def destroy
    @note.destroy!
    redirect_to dispatch_path, notice: "Draft #{@note.number} was deleted. Its pallets are ready to go again.", status: :see_other
  end

  def mark_dispatched
    on = params[:dispatched_on].present? ? Date.iso8601(params[:dispatched_on]) : Date.current
    @note.mark_dispatched!(user: Current.user, on:)
    notice = "#{@note.number} is dispatched."
    notice += " Order #{@note.sales_order.number} has gone out in full." if @note.sales_order.reload.dispatched?
    redirect_to @note, notice:, status: :see_other
  rescue ArgumentError, Date::Error => e
    redirect_to @note, alert: e.message, status: :see_other
  end

  def undo_dispatch
    @note.undo_dispatch!
    redirect_to @note, notice: "#{@note.number} is back to draft.", status: :see_other
  rescue ArgumentError => e
    redirect_to @note, alert: e.message, status: :see_other
  end

  private
    def set_note
      @note = DeliveryNote.includes(sales_order: [ :customer, :lines ]).find(params[:id])
    end

    def require_draft
      return if @note.draft?

      redirect_to @note, alert: "#{@note.number} has been dispatched, so it can't change. Undo the dispatch first.", status: :see_other
    end

    def note_params
      params.fetch(:delivery_note, {}).permit(:haulier, :vehicle_reg, :delivery_address, :notes)
    end

    # The ticked pallets, only from those offered, as [run_id, pallet_no].
    def chosen_keys(pallets)
      chosen = Array(params[:pallets]).map(&:to_s)
      pallets.select { chosen.include?(_1.key) }.map { [ _1.run.id, _1.pallet_no ] }
    end
end
