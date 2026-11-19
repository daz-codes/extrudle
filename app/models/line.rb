class Line < ApplicationRecord
  include Deactivatable

  has_many :line_rates, dependent: :restrict_with_error
  has_many :schedule_blocks, dependent: :restrict_with_error
  has_many :production_runs, dependent: :restrict_with_error

  normalizes :name, with: ->(n) { n.strip.upcase }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :default_changeover_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :position, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :name) }

  def to_s = name
end
