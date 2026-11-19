# Every change to stock is one of these (see CLAUDE.md). quantity_g is signed:
# receipts add, issues take away, adjustments go either way, transfers are 0
# and record the lot moving from one location to another.
class StockMovement < ApplicationRecord
  belongs_to :lot, inverse_of: :movements
  belongs_to :user, optional: true
  # Set on issue_to_production movements: the run that used the material.
  belongs_to :production_run, optional: true

  enum :kind, {
    receipt: "receipt", transfer: "transfer", issue_to_production: "issue_to_production", adjustment: "adjustment"
  }, validate: true

  validates :quantity_g, numericality: { only_integer: true }
  validates :quantity_g, numericality: { equal_to: 0 }, if: :transfer?
  validates :quantity_g, numericality: { other_than: 0 }, unless: :transfer?
  validates :quantity_g, numericality: { greater_than: 0 }, if: :receipt?
  validates :from_location, :to_location, inclusion: { in: Lot::LOCATIONS.keys }, allow_nil: true
  validates :moved_at, presence: true
  validates :production_run, presence: true, if: :issue_to_production?

  before_validation { self.moved_at ||= Time.current }

  scope :recent_first, -> { order(moved_at: :desc, id: :desc) }
  # Movements are history: correct a mistake with another movement, never by editing one.
  def readonly? = !new_record?
end
