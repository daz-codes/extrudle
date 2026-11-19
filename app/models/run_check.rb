# One check on a production log: a yes/no answer, or a width or thickness
# reading with the target and tolerance it was judged against.
# Record them with ProductionRun#record_check / #record_measurement.
class RunCheck < ApplicationRecord
  belongs_to :production_run, inverse_of: :checks
  belongs_to :user, optional: true

  validates :stage, inclusion: { in: ProductionRun::Checklist::STAGES }
  validates :passed, inclusion: { in: [ true, false ] }
  validates :checked_at, presence: true
  validate :known_item
  validates :target, :min_value, :max_value, :actual, presence: true, numericality: { only_integer: true }, if: :measurement?
  validates :actual, numericality: { greater_than: 0 }, if: :measurement?

  before_validation { self.checked_at ||= Time.current }
  before_validation :judge, if: :measurement?

  # "252" µm, or ".252" / "0.252" mm as written on the paper plan. Widths are whole mm.
  def self.parse_reading(item, input)
    text = input.to_s.strip
    raise ArgumentError, "can't be blank" if text.empty?

    if item.to_s == "thickness" && text.include?(".")
      DecimalInput.to_scaled_integer(text, 1_000, exact: true)
    else
      DecimalInput.to_scaled_integer(text, 1, exact: true)
    end
  rescue DecimalInput::TooPrecise
    raise ArgumentError, item.to_s == "thickness" ? "can't be finer than 1 µm" : "must be whole millimetres"
  rescue DecimalInput::Invalid
    raise ArgumentError, "is not a number"
  end

  def measurement? = ProductionRun::Checklist.measurement?(stage, item)

  def label = ProductionRun::Checklist.label(item)

  def difference = actual - target

  private
    def judge
      self.passed = actual.between?(min_value, max_value) if actual && min_value && max_value
    end

    def known_item
      return if measurement? || ProductionRun::Checklist.yes_no?(stage, item)

      errors.add(:item, "isn't a #{stage.to_s.humanize.downcase} check")
    end
end
