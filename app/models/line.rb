class Line < ApplicationRecord
  include Deactivatable

  has_many :line_rates, dependent: :restrict_with_error
  # The live plan. Draft blocks are read through Schedule::Plan.
  has_many :schedule_blocks, -> { live }
  has_many :all_schedule_blocks, class_name: "ScheduleBlock", dependent: :restrict_with_error
  has_many :production_runs, dependent: :restrict_with_error

  normalizes :name, with: ->(n) { n.strip.upcase }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :default_changeover_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  # Used for specs with no rate of their own on this line (§11 Q89).
  validates :default_kg_per_hour, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :position, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :name) }

  def to_s = name
end
