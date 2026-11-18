# Slices a line's blocks into one row per day for the week timeline
# (PLAN.md §3: 48 × 30-minute slots per day). Days are UK days, so the
# clock-change Sundays have 46 or 50 slots. A block that crosses midnight
# appears on both days, marked as continuing.
#
#   timeline = Schedule::Timeline.new(blocks, week_start: Date.new(2026, 11, 16))
#   timeline.days.first.segments.first.from_slot #=> 13 (06:00)
class Schedule::Timeline
  Day = Data.define(:date, :starts_at, :ends_at, :slots, :segments) do
    def today? = date == Date.current

    # Where "now" falls across the day, as a percentage, or nil if not today.
    def now_percent(now = Time.current)
      return unless now >= starts_at && now < ends_at

      ((now - starts_at) / (ends_at - starts_at) * 100).round(3)
    end

    # [slot number (1-based), time] for each whole hour, for labels.
    def hours
      (0...slots).filter_map do |slot|
        time = starts_at + (slot * Schedule::SLOT_MINUTES).minutes
        [ slot + 1, time ] if time.min.zero?
      end
    end
  end

  # from_slot is the first grid column (1-based) and to_slot the column line it
  # ends at, so a block filling 06:00–07:00 is from_slot 13, to_slot 15.
  Segment = Data.define(:block, :from_slot, :to_slot, :continues_before, :continues_after) do
    def span = to_slot - from_slot
  end

  attr_reader :week_start

  def initialize(blocks, week_start:)
    @blocks = blocks.sort_by(&:starts_at)
    @week_start = week_start
  end

  def days
    @days ||= (week_start...(week_start + 7)).map { day_for(_1) }
  end

  def self.week_start_for(date)
    date.beginning_of_week(:monday)
  end

  private
    def day_for(date)
      starts_at = date.in_time_zone.beginning_of_day
      ends_at = (date + 1).in_time_zone.beginning_of_day
      segments = @blocks.select { _1.starts_at < ends_at && _1.ends_at > starts_at }.map do |block|
        from = [ block.starts_at, starts_at ].max
        to = [ block.ends_at, ends_at ].min
        Segment.new(block:, from_slot: slot(starts_at, from) + 1, to_slot: slot(starts_at, to) + 1,
                    continues_before: block.starts_at < starts_at, continues_after: block.ends_at > ends_at)
      end
      Day.new(date:, starts_at:, ends_at:, slots: slot(starts_at, ends_at), segments:)
    end

    def slot(day_start, time)
      ((time - day_start) / Schedule::SLOT_SECONDS).to_i
    end
end
