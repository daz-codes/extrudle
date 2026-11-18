# The production planner (PLAN.md §3). Each line has an ordered queue of
# ScheduleBlocks. Times are calculated, not typed: see Schedule::Reflow.
module Schedule
  SLOT_MINUTES = 30
  SLOT_SECONDS = SLOT_MINUTES * 60
  SLOTS_PER_DAY = 48

  class Error < StandardError; end

  module_function

  def round_up_to_slot(minutes)
    ((minutes + SLOT_MINUTES - 1) / SLOT_MINUTES) * SLOT_MINUTES
  end

  # The next 30-minute boundary at or after time. UK offsets are whole hours,
  # so UTC and Europe/London slots line up.
  def snap_up(time)
    seconds = time.to_i
    snapped = ((seconds + SLOT_SECONDS - 1) / SLOT_SECONDS) * SLOT_SECONDS
    Time.zone.at(snapped)
  end

  def on_slot?(time)
    time.to_i % SLOT_SECONDS == 0
  end

  # 90 => "1h 30m", 30 => "30m", 0 => "0m"
  def duration_text(minutes)
    hours, mins = minutes.divmod(60)
    [ ("#{hours}h" if hours.positive?), ("#{mins}m" if mins.positive?) ].compact.join(" ").presence || "0m"
  end

  # Minutes to make planned_g at kg_per_hour, rounded up to whole slots.
  # Integer maths only: grams × 60 ÷ (grams per hour), rounded up.
  def job_minutes(planned_g, kg_per_hour)
    grams_per_hour = kg_per_hour * Weight::GRAMS_PER_KG
    minutes = (planned_g * 60 + grams_per_hour - 1) / grams_per_hour
    [ round_up_to_slot(minutes), SLOT_MINUTES ].max
  end
end
