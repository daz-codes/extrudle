# Edits one line's plan. Every change rebuilds the automatic changeovers,
# reflows the line and updates the affected orders' open/scheduled status,
# all in one transaction.
#
#   editor = Schedule::Editor.new(line)
#   job = editor.add_job(order_line)                  # plans what's left of the line
#   editor.add(ScheduleBlock.new(kind: "planned_maintenance", duration_minutes: 240,
#                                locked: true, starts_at: Time.zone.parse("2026-11-20 14:00")))
#   editor.move(job, :up)
#   editor.remove(job)
#
# The queue of unlocked blocks starts at line.queue_starts_at, which only changes
# when the planner sets it (start_at, or starts_at: on add), or when an unlocked
# block is placed before it.
#
# Changeovers between jobs are automatic (§11 Q17): after every edit, each job
# whose spec differs from the previous job in the queue gets an automatic
# changeover just before it, unless the planner already put a changeover there.
# Automatic changeovers are rebuilt each time; the planner's own are kept.
#
# The editor works on the live plan, or on a draft plan (Slice 7e):
#
#   Schedule::Editor.new(line, plan: PlanDraft.current.plan)
#
# Only live edits change order statuses; a draft changes nothing real until
# it's published (Schedule::Publish).
#
# Failures raise Schedule::Error with a message for the planner.
class Schedule::Editor
  AUTOMATIC_MESSAGE = "This changeover is added automatically between jobs for different specs, and moves with them"

  attr_reader :line, :plan

  def initialize(line, plan: Schedule::Plan.live)
    @line = line
    @plan = plan
  end

  # Puts an order line on this line's queue. planned_g defaults to whatever is still unplanned.
  def add_job(order_line, planned_g: nil, position: nil, duration_minutes: nil, starts_at: nil)
    order = order_line.sales_order
    ensure_order_editable!(order)

    raise Schedule::Error, "Planned weight must be more than 0" if planned_g && !planned_g.positive?

    planned_g ||= plan.unplanned_g(order_line)
    raise Schedule::Error, "#{order.number} #{order_line.product_spec} is already fully planned" unless planned_g.positive?

    job = ScheduleBlock.new(line: line, kind: "job", sales_order_line: order_line, planned_g: planned_g,
                            duration_minutes: duration_minutes || Schedule::SLOT_MINUTES)
    add(job, position: position, starts_at: starts_at)
  end

  # Adds any block. Unlocked blocks join the queue at position (1-based, among
  # the line's blocks in time order) or at the end. Locked blocks need starts_at.
  #
  # starts_at: on an unlocked block sets when the line's queue starts.
  def add(block, position: nil, starts_at: nil)
    block.line = line
    block.plan_draft = plan.draft
    raise Schedule::Error, "A locked block needs a start time" if block.locked? && block.starts_at.blank?

    block.starts_at = Schedule.snap_up(block.starts_at) if block.locked? # same as lock: snap to the next slot
    validate_position!(position) if position
    edit(starts_at: starts_at) do |blocks|
      block.queue_key = position ? queue_key_before(blocks, position) : queue_end(blocks) unless block.locked?
      blocks << block
    end
    block
  end

  # Swaps an unlocked block with the previous or next one in the queue
  # (changeovers are skipped; they're rebuilt). Locked blocks stay put.
  def move(block, direction)
    edit do |blocks|
      block = find_movable(blocks, block)
      queue = flowing(blocks).reject(&:automatic?)
      index = queue.index(block)
      other_index = direction.to_sym == :up ? index - 1 : index + 1
      next unless other_index.between?(0, queue.size - 1)

      other = queue[other_index]
      ensure_order_editable!(other.sales_order) if other.job?
      ensure_not_started!(other)
      block.queue_key, other.queue_key = other.queue_key, block.queue_key
    end
  end

  # Moves an unlocked block so it sits at position (1-based) in the line.
  def move_to(block, position)
    validate_position!(position)
    edit do |blocks|
      block = find_movable(blocks, block)
      block.queue_key = queue_key_before(blocks - [ block ], position)
    end
  end

  # New duration for a non-job block, or a manual estimate for a job with no rate.
  def resize(block, duration_minutes)
    update(block, duration_minutes: duration_minutes)
  end

  def replan(job, planned_g)
    update(job, planned_g: planned_g)
  end

  def lock(block, starts_at: nil)
    update(block, locked: true, starts_at: starts_at)
  end

  # Returns a locked block to the queue at the point in time it already sits,
  # so it doesn't move. If it's before the queue's start, the queue starts there.
  def unlock(block)
    update(block, locked: false)
  end

  # Applies any mix of changes to one block in a single edit (one reflow).
  # Only the keywords given are changed:
  #
  #   editor.update(job, planned_g: 2_000_000, locked: true, starts_at: time, notes: "Trial", colour: "mango")
  def update(block, **changes)
    unknown = changes.keys - %i[ planned_g duration_minutes locked starts_at notes colour ]
    raise ArgumentError, "unknown changes: #{unknown.join(", ")}" if unknown.any?

    edit do |blocks|
      block = find(blocks, block)
      ensure_order_editable!(block.sales_order) if block.job?

      apply_planned_g(block, changes[:planned_g]) if changes.key?(:planned_g)
      apply_duration(block, changes[:duration_minutes]) if changes.key?(:duration_minutes)
      apply_lock(blocks, block, changes[:locked], changes[:starts_at]) if changes.key?(:locked) || changes.key?(:starts_at)
      block.notes = changes[:notes].presence if changes.key?(:notes)
      block.colour = changes[:colour] if changes.key?(:colour)
    end
  end

  def remove(block)
    edit do |blocks|
      block = find(blocks, block)
      ensure_order_editable!(block.sales_order) if block.job?
      ensure_not_started!(block)
      raise Schedule::Error, AUTOMATIC_MESSAGE if block.automatic?

      discard(blocks, block)
    end
  end

  # Takes every job for an order off this line in one edit.
  def remove_jobs_for(order)
    edit do |blocks|
      blocks.select { _1.job? && _1.sales_order_line.sales_order_id == order.id }.each { discard(blocks, _1) }
    end
  end

  # Restarts the line's queue at a new time (e.g. the plan starts Monday 06:00).
  def start_at(time)
    edit(starts_at: time) { }
  end

  # Re-times the line, e.g. after a line rate changes.
  def reflow
    edit { }
  end

  # Takes every job for an order off all lines (e.g. when it's cancelled), on
  # the live plan and on the draft if there is one (§11 Q55).
  def self.unschedule(order)
    [ Schedule::Plan.live, Schedule::Plan.current ].uniq.each do |plan|
      Line.where(id: plan.blocks.jobs.where(sales_order_line_id: order.lines.select(:id)).select(:line_id))
        .each { new(_1, plan:).remove_jobs_for(order) }
    end
  end

  private
    def edit(starts_at: nil)
      ScheduleBlock.transaction do
        blocks = load_blocks
        @anchor = starts_at ? Schedule.snap_up(starts_at) : queue_start(blocks)
        @removed = []
        blocks.reject(&:locked?).each { _1.queue_key ||= _1.position }
        yield blocks

        rebuild_changeovers(blocks)
        @removed.select(&:persisted?).each(&:destroy!)
        @anchor ||= Schedule.snap_up(Time.current) if blocks.any? { !_1.locked? }
        plan.set_queue_start(line, @anchor)
        Schedule::Reflow.new(line, blocks: blocks, starts_at: @anchor).call
        refresh_orders(blocks) if plan.live?
      end
    rescue StandardError => e
      line.reload # the transaction rolled back; don't leave an unsaved queue start in memory
      raise Schedule::Error, "#{e.record}: #{e.record.errors.full_messages.to_sentence}" if e.is_a?(ActiveRecord::RecordInvalid)

      raise
    end

    # The stored start, falling back to the earliest unlocked block for lines planned before it was stored.
    def queue_start(blocks)
      plan.queue_start(line) || blocks.reject(&:locked?).filter_map(&:starts_at).min
    end

    def load_blocks
      plan.blocks_for(line).includes(:source_block, sales_order_line: [ :sales_order, { product_spec: :line_rates } ]).to_a
    end

    def apply_planned_g(block, planned_g)
      return if planned_g == block.planned_g
      raise Schedule::Error, "Only jobs have a planned weight" unless block.job?
      raise Schedule::Error, "Planned weight must be more than 0" unless planned_g.to_i.positive?

      block.planned_g = planned_g
    end

    def apply_duration(block, minutes)
      return if minutes == block.duration_minutes
      raise Schedule::Error, AUTOMATIC_MESSAGE if block.automatic?
      raise Schedule::Error, "#{block} takes as long as the line rate says. Change the planned weight instead." if block.job? && block.line_rate

      block.duration_minutes = minutes
    end

    # locked: true pins the block (at starts_at, snapped, or where it is now).
    # locked: false returns it to the queue where it sits in time.
    # starts_at alone moves an already locked block.
    def apply_lock(blocks, block, locked, starts_at)
      locked = block.locked? if locked.nil?
      raise Schedule::Error, AUTOMATIC_MESSAGE if block.automatic? && locked

      if locked
        block.locked = true
        block.starts_at = Schedule.snap_up(starts_at) if starts_at
      elsif block.locked?
        later = flowing(blocks).detect { _1.starts_at && _1.starts_at >= block.starts_at }
        block.locked = false
        block.queue_key = later ? later.queue_key - BigDecimal("0.5") : queue_end(blocks)
        @anchor = block.starts_at if @anchor.nil? || block.starts_at < @anchor
      end
    end

    def find(blocks, block)
      blocks.detect { _1.id == block.id } || raise(Schedule::Error, "That block isn't on line #{line.name}")
    end

    def find_movable(blocks, block)
      block = find(blocks, block)
      raise Schedule::Error, "Locked blocks can't be moved. Unlock it first." if block.locked?
      raise Schedule::Error, AUTOMATIC_MESSAGE if block.automatic?

      ensure_order_editable!(block.sales_order) if block.job?
      ensure_not_started!(block)
      block
    end

    def discard(blocks, block)
      blocks.delete(block)
      @removed << block
    end

    # Orders still to make (open, scheduled or in production) can be planned.
    # Starting one job puts the order in production, and its other jobs and
    # unplanned lines must stay plannable.
    def ensure_order_editable!(order)
      return if SalesOrder::ACTIVE_STATUSES.include?(order.status)

      raise Schedule::Error, "Order #{order.number} is #{order.status.humanize.downcase}, so its plan can't change"
    end

    # A job with a production log has started: it can still be resized, re-timed
    # or re-noted, but not moved in the queue or taken off the plan. A draft
    # block counts as started when its live job has (even after the draft began).
    def ensure_not_started!(block)
      return unless block.persisted? && block.started?

      raise Schedule::Error, "This job has started (it has a production log), so it can't be moved or removed"
    end

    def validate_position!(position)
      raise Schedule::Error, "Position must be 1 or more" unless position.is_a?(Integer) && position >= 1
    end

    def flowing(blocks)
      blocks.reject(&:locked?).sort_by { [ _1.queue_key || Float::INFINITY, _1.id || Float::INFINITY ] }
    end

    def queue_end(blocks)
      (flowing(blocks).filter_map(&:queue_key).max || 0) + 1
    end

    # A key that sorts just before the unlocked block currently shown at position.
    def queue_key_before(blocks, position)
      in_time_order = blocks.sort_by { [ _1.starts_at || Time.zone.at(0), _1.position || 0 ] }
      target = in_time_order.drop(position - 1).detect { !_1.locked? }
      return queue_end(blocks) unless target

      target.queue_key - BigDecimal("0.5")
    end

    # An automatic changeover before each job whose spec differs from the previous
    # job in the queue, unless the planner's own changeover already sits between
    # them (§11 Q17). Existing automatic rows are reused where possible.
    def rebuild_changeovers(blocks)
      spare = flowing(blocks).select(&:automatic?)
      spare.each { blocks.delete(_1) }

      previous_job = nil
      manual_changeover = false
      flowing(blocks).each do |block|
        if block.changeover?
          manual_changeover = true
        elsif block.job?
          if !manual_changeover && needs_changeover?(previous_job, block)
            changeover = spare.shift || ScheduleBlock.new(line: line, plan_draft: plan.draft, kind: "changeover", automatic: true,
                                                          duration_minutes: Schedule.round_up_to_slot(line.default_changeover_minutes))
            changeover.queue_key = block.queue_key - BigDecimal("0.25")
            blocks << changeover
          end
          previous_job = block
          manual_changeover = false
        end
      end

      @removed.concat(spare)
    end

    def needs_changeover?(first, second)
      first && first.product_spec&.id != second.product_spec&.id && line.default_changeover_minutes.positive?
    end

    def refresh_orders(blocks)
      orders = (blocks + @removed).select(&:job?).map(&:sales_order).uniq
      orders.each(&:refresh_schedule_status!)
    end
end
