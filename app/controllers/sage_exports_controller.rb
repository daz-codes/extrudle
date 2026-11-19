# Sends dispatched delivery notes to Sage as a CSV file, and keeps every file
# sent so it can be downloaded again.
class SageExportsController < ApplicationController
  require_role :admin, :office

  def index
    @waiting = DeliveryNote.not_exported.includes(sales_order: [ :customer, :lines ]).order(:dispatched_on, :number).to_a
    @exports = SageExport.includes(:created_by).order(created_at: :desc).limit(20)
  end

  def create
    export = SageExport.create_from!(SageExport.ready_notes, user: Current.user)
    redirect_to sage_exports_path, notice: "Exported #{helpers.pluralize(export.delivery_notes.count, "delivery note")} to #{export.filename}. Download it below and import it into Sage."
  rescue SageExport::NothingToExport => e
    redirect_to sage_exports_path, alert: e.message
  end

  def show
    export = SageExport.find(params[:id])
    send_data export.csv, type: "text/csv", filename: export.filename
  end
end
