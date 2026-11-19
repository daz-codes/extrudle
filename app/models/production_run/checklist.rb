# The checks on the production log, and the tolerances measurements are judged by.
#
# Yes/no items are from form 5.4.1.2. Working assumption, see PLAN.md §11 Q35
# (exact wording) and Q36 (tolerances). Tolerances are kept on each RunCheck
# when it's recorded, so changing them here never changes old logs.
module ProductionRun::Checklist
  YES_NO = {
    "prestart" => {
      "previous_documents_removed" => "Previous documents and labels removed",
      "previous_product_cleared" => "Previous product cleared from the line"
    },
    # Working assumption, see PLAN.md §11 Q40.
    "line_clearance" => {
      "materials_cleared" => "Materials cleared from the line",
      "documents_removed" => "Log, labels and documents removed",
      "line_cleared" => "Line cleared for the next micron"
    }
  }.freeze

  MEASUREMENTS = {
    "width" => { label: "Width", unit: "mm" },
    "thickness" => { label: "Thickness", unit: "µm" }
  }.freeze

  # Stages where width and thickness are measured.
  MEASURED_STAGES = %w[ startup end_of_run ].freeze

  STAGES = %w[ prestart startup pallet end_of_run line_clearance ].freeze

  WIDTH_TOLERANCE_MM = 2
  THICKNESS_TOLERANCE_BP = 500 # ±5%

  module_function

  def items(stage) = YES_NO.fetch(stage.to_s, {})

  def yes_no?(stage, item) = items(stage).key?(item.to_s)

  def measurement?(stage, item) = MEASURED_STAGES.include?(stage.to_s) && MEASUREMENTS.key?(item.to_s)

  def label(item) = YES_NO.values.reduce(:merge)[item.to_s] || MEASUREMENTS.dig(item.to_s, :label) || item.to_s.humanize

  def unit(item) = MEASUREMENTS.dig(item.to_s, :unit)

  # [target, min, max] for a spec, in whole mm or microns.
  # ±5% of 250 µm is 237.5–262.5, so 238–262 µm (integer maths only).
  def range(item, spec)
    case item.to_s
    when "width"
      target = spec.width_mm
      [ target, target - WIDTH_TOLERANCE_MM, target + WIDTH_TOLERANCE_MM ]
    when "thickness"
      target = spec.thickness_micron
      [ target, (target * (10_000 - THICKNESS_TOLERANCE_BP) + 9_999) / 10_000, target * (10_000 + THICKNESS_TOLERANCE_BP) / 10_000 ]
    else
      raise ArgumentError, "#{item} isn't a measurement"
    end
  end
end
