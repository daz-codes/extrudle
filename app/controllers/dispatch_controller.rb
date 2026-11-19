# Dispatch: orders with pallets ready to go, delivery notes, and the Sage export.
# Office work. Working assumption, see PLAN.md §11 Q68.
class DispatchController < ApplicationController
  require_role :admin, :office

  def show
    @ready = SalesOrder.ready_to_dispatch
    @drafts = DeliveryNote.draft.includes(sales_order: :customer).recent_first
    @to_export = DeliveryNote.not_exported.includes(sales_order: :customer).order(:dispatched_on, :number)
    @recent = DeliveryNote.dispatched.where.not(exported_at: nil).includes(sales_order: :customer).order(dispatched_on: :desc, number: :desc).limit(20)
  end
end
