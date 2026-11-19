# Which plan is being read or edited: the live plan (blocks with no draft), or
# a draft. Schedule::Editor, Schedule::Warnings and the planner board take one.
#
#   Schedule::Plan.live              # what the floor runs
#   Schedule::Plan.current           # what the planner edits: the draft if there is one
#   Schedule::Plan.for(block)        # the plan a block belongs to
class Schedule::Plan
  attr_reader :draft

  def self.live = new(nil)

  def self.current
    draft = PlanDraft.current
    draft ? new(draft) : live
  end

  def self.for(block) = new(block.plan_draft)

  def initialize(draft)
    @draft = draft
  end

  def live? = draft.nil?
  def draft? = !live?

  def blocks = ScheduleBlock.where(plan_draft_id: draft&.id)

  def blocks_for(line) = blocks.where(line:)

  def queue_start(line)
    live? ? line.queue_starts_at : draft.queue_start(line)
  end

  def set_queue_start(line, time)
    if live?
      line.update!(queue_starts_at: time) if line.queue_starts_at != time
    else
      draft.set_queue_start(line, time)
    end
  end

  # Weight planned for an order line on this plan (all lines).
  def planned_g(order_line)
    if @planned_by_order_line
      @planned_by_order_line.fetch(order_line.id, 0)
    else
      blocks.jobs.where(sales_order_line: order_line).sum(:planned_g)
    end
  end

  def unplanned_g(order_line) = [ order_line.quantity_g.to_i - planned_g(order_line), 0 ].max

  # Loads every order line's planned weight in one query, for pages that show many.
  def preload_planned!
    @planned_by_order_line = blocks.jobs.group(:sales_order_line_id).sum(:planned_g)
    self
  end

  def ==(other) = other.is_a?(Schedule::Plan) && other.draft == draft
  alias eql? ==
  def hash = draft&.id.hash
end
