# Recalculates the times on one line's queue (PLAN.md §3).
#
# * Locked blocks (e.g. a booked engineer visit) never move.
# * Unlocked blocks run back to back in queue order from the line's start,
#   flowing around locked blocks. A block that would overlap a locked block
#   starts after it instead; jobs aren't split (PLAN.md §11 Q15), so the line
#   may sit idle before a locked block (Schedule::Warnings flags this).
# * Job durations are recalculated from planned weight and the line rate.
# * Positions are renumbered 1..n in time order.
#
#   Schedule::Reflow.new(line).call
#   Schedule::Reflow.new(line, blocks: edited_blocks, starts_at: time).call
class Schedule::Reflow
  attr_reader :line, :blocks

  def initialize(line, blocks: nil, starts_at: nil)
    @line = line
    @blocks = blocks || line.schedule_blocks.includes(sales_order_line: { product_spec: :line_rates }).to_a
    @starts_at = starts_at
  end

  def call
    place_blocks
    ScheduleBlock.transaction do
      # Positions are renumbered after placement, so clear them first to avoid
      # transient clashes, then save locked blocks before the ones flowing round them.
      blocks.sort_by { _1.locked? ? 0 : 1 }.each(&:save!)
    end
    blocks
  end

  # Computes times and positions in memory without saving.
  def place_blocks
    locked, flowing = blocks.partition(&:locked?)
    locked.each { |block| block.refresh_duration; block.place_at(block.starts_at) }
    locked.sort_by!(&:starts_at)

    cursor = Schedule.snap_up(anchor)
    queue(flowing).each do |block|
      block.refresh_duration
      cursor = first_free_start(cursor, block.duration_minutes, locked)
      block.place_at(cursor)
      cursor = block.ends_at
    end

    blocks.sort_by { [ _1.starts_at, _1.locked? ? 0 : 1 ] }.each.with_index(1) do |block, index|
      block.position = index
      block.queue_key = nil
    end
    blocks
  end

  private
    # Where the line's queue starts: an explicit time, else the earliest
    # unlocked block's current start, else now.
    def anchor
      @starts_at || blocks.reject(&:locked?).filter_map { _1.starts_at_was || _1.starts_at }.min || Time.current
    end

    def queue(flowing)
      flowing.sort_by { [ _1.queue_key || _1.position || Float::INFINITY, _1.id || Float::INFINITY ] }
    end

    def first_free_start(cursor, minutes, locked)
      loop do
        finish = cursor + minutes.minutes
        clash = locked.detect { _1.starts_at < finish && _1.ends_at > cursor }
        return cursor unless clash

        cursor = clash.ends_at
      end
    end
end
