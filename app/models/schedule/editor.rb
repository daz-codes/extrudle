# Edits one line's plan. Every change reflows the line and updates the
# affected orders' open/scheduled status, all in one transaction.
#
#   editor = Schedule::Editor.new(line)
#   job = editor.add_job(order_line)                  # plans what's left of the line
#   editor.add(ScheduleBlock.new(kind: "planned_maintenance", duration_minutes: 240,
#                                locked: true, starts_at: Time.zone.parse("2026-11-20 14:00")))
#   editor.move(job, :up)
#   editor.remove(job)
#
# Failures raise Schedule::Error with a message for the planner.
class Schedule::Editor
  attr_reader :line

  def initialize(line)
    @line = line
  end

  # Puts an order line on this line's queue. planned_g defaults to whatever is
  # still unplanned. A changeover is added between jobs for different specs (§11 Q17).
  def add_job(order_line, planned_g: nil, position: nil, duration_minutes: nil, starts_at: nil)
    order = order_line.sales_order
    raise Schedule::Error, "Order #{order.number} is #{order.status.humanize.downcase}, so it can't be planned" unless order.editable?

    order_line.schedule_blocks.reset
    planned_g ||= order_line.unplanned_g
    raise Schedule::Error, "#{order.number} #{order_line.product_spec} is already fully planned" unless planned_g.positive?

    job = ScheduleBlock.new(line: line, kind: "job", sales_order_line: order_line, planned_g: planned_g,
                            duration_minutes: duration_minutes || Schedule::SLOT_MINUTES)
    add(job, position: position, starts_at: starts_at)
  end

  # Adds any block. Unlocked blocks join the queue at position (1-based, among
  # the line's blocks in time order) or at the end. Locked blocks need starts_at.
  #
  # starts_at: on an unlocked block sets when the line's queue starts. Use it for
  # the first block on an empty line; otherwise the queue starts now.
  def add(block, position: nil, starts_at: nil)
    block.line = line
    raise Schedule::Error, "A locked block needs a start time" if block.locked? && block.starts_at.blank?

    queue_start = starts_at && Schedule.snap_up(starts_at)
    edit(starts_at: queue_start) do |blocks|
      unless block.locked?
        block.queue_key = position ? queue_key_before(blocks, position) : queue_end(blocks)
        blocks << block
        add_changeovers_around(block, blocks) if block.job?
      else
        blocks << block
      end
    end
    block
  end

  # Swaps an unlocked block with its neighbour in the queue. Locked blocks
  # stay put; the queue flows around them.
  def move(block, direction)
    edit do |blocks|
      block = find(blocks, block)
      raise Schedule::Error, "Locked blocks can't be moved. Unlock it first." if block.locked?

      queue = flowing(blocks)
      index = queue.index(block)
      other = queue[direction.to_sym == :up ? index - 1 : index + 1]
      next unless other && (direction.to_sym != :up || index.positive?)

      block.queue_key, other.queue_key = other.queue_key, block.queue_key
    end
  end

  # Moves an unlocked block so it sits at position (1-based) in the line.
  def move_to(block, position)
    edit do |blocks|
      block = find(blocks, block)
      raise Schedule::Error, "Locked blocks can't be moved. Unlock it first." if block.locked?

      block.queue_key = queue_key_before(blocks - [ block ], position)
    end
  end

  # New duration for a non-job block, or a manual estimate for a job with no rate.
  def resize(block, duration_minutes)
    edit do |blocks|
      block = find(blocks, block)
      raise Schedule::Error, "#{block} takes as long as the line rate says. Change the planned weight instead." if block.job? && block.line_rate

      block.duration_minutes = duration_minutes
    end
  end

  def replan(job, planned_g)
    edit do |blocks|
      job = find(blocks, job)
      job.planned_g = planned_g
    end
  end

  def lock(block, starts_at: nil)
    edit do |blocks|
      block = find(blocks, block)
      block.locked = true
      block.starts_at = Schedule.snap_up(starts_at) if starts_at
    end
  end

  def unlock(block)
    edit do |blocks|
      block = find(blocks, block)
      block.locked = false
      block.queue_key = block.position
    end
  end

  def remove(block)
    edit do |blocks|
      block = find(blocks, block)
      blocks.delete(block)
      @removed = block
    end
  end

  # Restarts the line's queue at a new time (e.g. the plan starts Monday 06:00).
  # Needs at least one unlocked block; for an empty line, pass starts_at: to add.
  def start_at(time)
    edit(starts_at: time) { }
  end

  # Takes every job for an order off all lines (e.g. when it's cancelled).
  def self.unschedule(order)
    lines = Line.joins(:schedule_blocks).merge(ScheduleBlock.jobs.where(sales_order_line_id: order.lines.select(:id))).distinct
    lines.each do |line|
      editor = new(line)
      line.schedule_blocks.jobs.where(sales_order_line_id: order.lines.select(:id)).each { editor.remove(_1) }
    end
  end

  private
    def edit(starts_at: nil)
      ScheduleBlock.transaction do
        blocks = load_blocks
        # Read the line's start before changing anything, so removing or moving
        # the first block doesn't shift the whole queue.
        anchor = starts_at || blocks.reject(&:locked?).filter_map(&:starts_at).min
        blocks.reject(&:locked?).each { _1.queue_key ||= _1.position }
        @removed = nil
        yield blocks

        @removed&.destroy! if @removed&.persisted?
        Schedule::Reflow.new(line, blocks: blocks, starts_at: anchor).call
        refresh_orders(blocks)
      end
    rescue ActiveRecord::RecordInvalid => e
      raise Schedule::Error, "#{e.record}: #{e.record.errors.full_messages.to_sentence}"
    end

    def load_blocks
      line.schedule_blocks.includes(sales_order_line: [ :sales_order, { product_spec: :line_rates } ]).to_a
    end

    def find(blocks, block)
      blocks.detect { _1.id == block.id } || raise(Schedule::Error, "That block isn't on line #{line.name}")
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

    def add_changeovers_around(job, blocks)
      queue = flowing(blocks)
      index = queue.index(job)
      before = index.positive? ? queue[index - 1] : nil
      after = queue[index + 1]

      add_changeover_between(before, job, blocks) if needs_changeover?(before, job)
      add_changeover_between(job, after, blocks) if needs_changeover?(job, after)
    end

    def needs_changeover?(first, second)
      first&.job? && second&.job? && first.sales_order_line.product_spec_id != second.sales_order_line.product_spec_id &&
        line.default_changeover_minutes.positive?
    end

    def add_changeover_between(first, second, blocks)
      changeover = ScheduleBlock.new(line: line, kind: "changeover",
                                     duration_minutes: Schedule.round_up_to_slot(line.default_changeover_minutes))
      changeover.queue_key = (first.queue_key + second.queue_key) / 2
      blocks << changeover
    end

    def refresh_orders(blocks)
      order_lines = blocks.filter_map(&:sales_order_line)
      order_lines << @removed.sales_order_line if @removed&.job?
      order_lines.uniq.each { _1.schedule_blocks.reset } # planned weights have changed
      order_lines.map(&:sales_order).uniq.each(&:refresh_schedule_status!)
    end
end
