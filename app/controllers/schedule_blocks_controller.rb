# Planner edits. Every change goes through Schedule::Editor (see CLAUDE.md).
# Turbo requests get the board back as a stream; plain requests are redirected.
class ScheduleBlocksController < ApplicationController
  include PlannerBoard
  require_role :admin, :office
  before_action :set_block, only: %i[ edit update destroy move drop ]
  before_action :keep_live_plan_while_drafting, only: %i[ edit update destroy move drop ]

  # Adds to the plan being edited: the draft if there is one.
  def create
    @line = Line.active.find(params[:line_id])
    @plan = Schedule::Plan.current
    editor = Schedule::Editor.new(@line, plan: @plan)

    block = if params[:sales_order_line_id].present?
      order_line = SalesOrderLine.find(params[:sales_order_line_id])
      editor.add_job(order_line, planned_g: weight_param(:planned_kg), duration_minutes: hours_param,
                                 position: position_param, starts_at: time_param(:queue_starts_at))
    else
      editor.add(new_block, position: position_param, starts_at: time_param(:queue_starts_at))
    end

    done "Added #{block} to line #{@line.name}."
  rescue Schedule::Error, ArgumentError => e
    failed e.message
  end

  def edit
    @warnings = Schedule::Warnings.for_line(@line, plan: @plan.preload_planned!)[@block] || []
  end

  # Everything on the edit form is applied in one Schedule::Editor edit (one reflow).
  def update
    Schedule::Editor.new(@line, plan: @plan).update(@block, **block_changes)
    redirect_to planner_path_for(@line, Schedule::Timeline.week_start_for(@block.reload.starts_at.to_date)), notice: "#{@block} was updated."
  rescue Schedule::Error, ArgumentError, ActiveRecord::RecordInvalid => e
    @block.reload
    @warnings = Schedule::Warnings.for_line(@line, plan: @plan.preload_planned!)[@block] || []
    flash.now[:alert] = e.message
    render :edit, status: :unprocessable_content
  end

  def destroy
    Schedule::Editor.new(@line, plan: @plan).remove(@block)
    done "Removed #{@block} from line #{@line.name}."
  rescue Schedule::Error => e
    failed e.message
  end

  def move
    Schedule::Editor.new(@line, plan: @plan).move(@block, params[:direction] == "up" ? :up : :down)
    done nil
  rescue Schedule::Error => e
    failed e.message
  end

  # Dragged on the timeline to a new start (Slice 10). A queued block moves to
  # that place in the queue and the line reflows (§11 Q74); a locked block is
  # pinned at the new time (§11 Q75).
  def drop
    at = time_param(:at) || raise(ArgumentError, "Choose a time to move it to")
    editor = Schedule::Editor.new(@line, plan: @plan)
    @block.locked? ? editor.lock(@block, starts_at: at) : editor.move_to_time(@block, at)
    @block.reload
    done "#{@block} now runs #{helpers.plan_range(@block)}."
  rescue Schedule::Error, ArgumentError => e
    failed e.message
  end

  private
    def set_block
      @block = ScheduleBlock.find(params[:id])
      @line = @block.line
      @plan = Schedule::Plan.for(@block)
    end

    # While a new plan is drafted, the live plan can't be changed from the
    # planner. Working assumption, see PLAN.md §11 Q52.
    def keep_live_plan_while_drafting
      return unless @plan.live? && PlanDraft.current

      @plan = Schedule::Plan.current
      failed "A new plan is being drafted, so the live plan can't change. Make the change in the draft, or discard it first."
    end

    # Only what the form sent. Unchanged values are no-ops in the editor.
    def block_changes
      changes = {}
      changes[:planned_g] = weight_param(:planned_kg) if @block.job? && params[:planned_kg].present?
      changes[:duration_minutes] = hours_param if params[:duration_hours].present?
      changes[:locked] = params[:locked] == "1" if params.key?(:locked)
      changes[:starts_at] = time_param(:starts_at) if params[:locked] == "1" && params[:starts_at].present?
      changes[:notes] = params[:notes] if params.key?(:notes)
      changes[:colour] = job_colour(params[:colour]) if @block.job? && params.key?(:colour)
      changes
    end

    def new_block
      kind = params[:kind].to_s
      raise ArgumentError, "Choose what kind of block to add" unless ScheduleBlock::ADDABLE_KINDS.include?(kind)

      minutes = hours_param || raise(ArgumentError, "Enter how long it takes")
      locked = params[:locked] == "1"
      ScheduleBlock.new(kind: kind, duration_minutes: minutes, locked: locked, notes: params[:notes].presence,
                        starts_at: (time_param(:starts_at) if locked))
    end

    # Hours as typed ("1.5") to minutes, exactly. Blank means "not given".
    def hours_param
      return if params[:duration_hours].blank?

      DecimalInput.to_scaled_integer(params[:duration_hours], 60, exact: true)
    rescue DecimalInput::Invalid
      raise ArgumentError, "Duration must be a number of hours in steps of 0.5"
    end

    def weight_param(name)
      return if params[name].blank?

      Weight.parse(params[name])
    rescue Weight::InvalidInput
      raise ArgumentError, "Planned weight must be a number of kg"
    end

    def time_param(name)
      return if params[name].blank?

      Time.zone.parse(params[name]) || raise(ArgumentError, "That isn't a valid date and time")
    end

    def position_param
      params[:position].presence&.to_i
    end

    def done(message)
      flash.now[:notice] = message if message
      respond_to do |format|
        format.turbo_stream { render_board }
        format.html { redirect_to planner_path_for(@line, Schedule::Timeline.week_start_for(week_param)), notice: message }
      end
    end

    def failed(message)
      flash.now[:alert] = message
      respond_to do |format|
        format.turbo_stream { render_board(status: :unprocessable_content) }
        format.html { redirect_to planner_path_for(@line, Schedule::Timeline.week_start_for(week_param)), alert: message }
      end
    end

    # The customer's own colour is stored as nil, so the job keeps following
    # the customer if theirs changes later.
    def job_colour(picked)
      picked.presence unless picked == @block.sales_order.customer.colour
    end
end
