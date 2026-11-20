# Spreadsheet imports for go-live (PLAN.md Slice 9). Upload a CSV, see every
# row checked, then import it all or nothing. Office and admin only.
class ImportsController < ApplicationController
  include MasterData
  MAX_BYTES = 2.megabytes

  before_action :set_kind, except: :index

  def index
  end

  def show
  end

  def template
    send_data @kind_class.template_csv, type: "text/csv", filename: "extrudle-#{@kind.dasherize}-template.csv"
  end

  def preview
    @csv = uploaded_text
    return redirect_to(import_path(@kind), alert: "Choose a CSV file to check.") if @csv.blank?

    @import = @kind_class.new(@csv)
    @import.preview
    render :preview
  rescue ArgumentError => e
    redirect_to import_path(@kind), alert: e.message
  end

  def run
    @csv = params[:csv].to_s
    return redirect_to(import_path(@kind), alert: "That file is too big (2 MB at most).") if @csv.bytesize > MAX_BYTES

    @import = @kind_class.new(@csv)
    if @import.save
      counts = @import.counts.map { |action, count| "#{count} #{action}" }.to_sentence
      redirect_to import_path(@kind), notice: "Imported #{@kind_class.title.downcase}: #{counts}."
    else
      flash.now[:alert] = "Nothing was imported. Fix the rows below and upload the file again."
      render :preview, status: :unprocessable_content
    end
  end

  private
    def set_kind
      @kind = params[:kind].to_s
      @kind_class = Import.kind_class(@kind)
    rescue KeyError
      redirect_to imports_path, alert: "There's no import for #{@kind}."
    end

    def uploaded_text
      file = params[:file]
      return if file.blank?
      raise ArgumentError, "That file is too big (2 MB at most)." if file.size > MAX_BYTES

      file.read
    end
end
