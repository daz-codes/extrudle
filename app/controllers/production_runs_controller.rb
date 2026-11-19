# Production logs. Every role can use them: technicians fill them in on the
# floor, the office reads and corrects them (Working assumption, PLAN.md §11 Q39).
class ProductionRunsController < ApplicationController
  include FloorOrOfficeLayout
  before_action :set_run, only: %i[ show edit update ]
  before_action :require_running, only: %i[ edit update ]

  def index
    @board = ProductionRun::Board.new
    @runs = ProductionRun.includes(:line, :product_spec, sales_order_line: { sales_order: :customer }).recent_first.limit(50)
  end

  def show
    respond_to do |format|
      format.html
      format.pdf do
        pdf = ProductionLogPdf.new(@run, printed_by: Current.user)
        send_data pdf.render, type: "application/pdf", disposition: "inline", filename: pdf.filename
      end
    end
  end

  def new
    @start = ProductionRun::Start.new(schedule_block: ScheduleBlock.jobs.find(params[:block]))
  end

  def create
    block = ScheduleBlock.jobs.find(params.dig(:production_run_start, :schedule_block_id))
    @start = ProductionRun::Start.new(schedule_block: block, **start_params)
    @start.user = Current.user

    if @start.save
      redirect_to @start.run, notice: "Despatch #{@start.run.despatch_number} started. Do the prestart checks next."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @run.update(run_params)
      redirect_to return_to_finish? ? production_run_finish_path(@run) : @run, notice: "Despatch #{@run.despatch_number} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    # The edit page was opened from the End of run tab (to add a comment), so go back there.
    def return_to_finish? = params[:return_to] == "finish"
    helper_method :return_to_finish?

    def set_run
      @run = ProductionRun.includes(:line, :product_spec, :reels, :started_by, :finished_by, checks: :user, material_loads: { lot: :material },
                                    sales_order_line: { sales_order: :customer }).find(params[:id])
    end

    def require_running
      redirect_to @run, alert: "Despatch #{@run.despatch_number} is finished, so it can't be changed." unless @run.editable?
    end

    def start_params
      params.expect(production_run_start: %i[ despatch_number started_at technician_days technician_nights
                                              antiblock_batch_no silicone_batch_no pe_film_batch_no ]).to_h.symbolize_keys
    end

    def run_params
      params.expect(production_run: %i[ technician_days technician_nights antiblock_batch_no silicone_batch_no
                                        pe_film_batch_no special_instructions comments ])
    end
end
