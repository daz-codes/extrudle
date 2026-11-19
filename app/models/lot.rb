# A bag, octabin or batch of one material, with its own code and label.
# Its weight is the sum of its stock movements and is never edited directly:
# change it through Stock::Receipt, Stock::Transfer and Stock::Adjustment.
class Lot < ApplicationRecord
  CODE_PREFIX = "L" # L-2026-000123. Working assumption, see PLAN.md §11 Q30.

  LOCATIONS = {
    "on_site" => "On site",
    "storage" => "Storage",
    "at_supplier" => "At supplier",
    "in_transit" => "In transit"
  }.freeze

  belongs_to :material
  belongs_to :purchase_order_line, optional: true
  has_many :movements, -> { order(:moved_at, :id) }, class_name: "StockMovement", inverse_of: :lot, dependent: :restrict_with_error
  has_many :material_loads, -> { order(:loaded_at, :id) }, dependent: :restrict_with_error

  enum :location, LOCATIONS.keys.index_by(&:itself), validate: true

  normalizes :supplier_lot_ref, :bag_no, :delivery_ref, with: ->(text) { text.strip.presence }

  validates :code, presence: true, uniqueness: true
  validates :received_on, presence: true
  validates :initial_g, numericality: { only_integer: true, greater_than: 0 }
  validate :material_matches_po_line

  # Adds quantity_g (the current weight) to each lot, in one query.
  scope :with_quantity, -> {
    select("lots.*", "(SELECT COALESCE(SUM(stock_movements.quantity_g), 0) FROM stock_movements WHERE stock_movements.lot_id = lots.id) AS quantity_g")
  }
  scope :in_stock, -> { where("(SELECT COALESCE(SUM(stock_movements.quantity_g), 0) FROM stock_movements WHERE stock_movements.lot_id = lots.id) > 0") }
  scope :by_code, -> { order(:code) }
  scope :search, ->(q) {
    next all if q.blank?
    like = "%#{sanitize_sql_like(q)}%"
    left_joins(:material).where("lots.code LIKE :q OR lots.supplier_lot_ref LIKE :q OR lots.bag_no LIKE :q OR lots.delivery_ref LIKE :q OR materials.name LIKE :q", q: like)
  }

  # The next free codes for a year: L-2026-000001, L-2026-000002 …
  def self.next_codes(count, year: Date.current.year)
    prefix = "#{CODE_PREFIX}-#{year}-"
    start = prefix.length + 1
    last = where("code LIKE ?", "#{prefix}%").pick(Arel.sql(sanitize_sql_array([ "MAX(CAST(SUBSTR(code, ?) AS INTEGER))", start ]))).to_i
    (1..count).map { |n| format("%s%06d", prefix, last + n) }
  end

  def self.location_label(location) = LOCATIONS.fetch(location.to_s)

  # The current weight in grams.
  def quantity_g
    has_attribute?(:quantity_g) ? self[:quantity_g] : movements.sum(:quantity_g)
  end

  def empty? = quantity_g <= 0

  # Marked empty on the line (see Stock::Reconciliation). Its book weight is
  # zeroed once every log that used it has finished.
  def emptied? = emptied_at.present?
  def reconciled? = reconciled_at.present?

  # What production runs have used, in grams (positive).
  def used_g = -movements.select(&:issue_to_production?).sum(&:quantity_g)

  def location_label = self.class.location_label(location)

  def purchase_order = purchase_order_line&.purchase_order

  def supplier = purchase_order&.supplier || material.supplier

  def to_s = code

  private
    def material_matches_po_line
      return unless purchase_order_line && material_id != purchase_order_line.material_id

      errors.add(:material, "must match the purchase order line")
    end
end
