class MaterialCategory < ApplicationRecord
  has_many :materials, dependent: :restrict_with_error

  normalizes :name, with: ->(n) { n.squish }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :position, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :name) }

  def to_s = name
end
