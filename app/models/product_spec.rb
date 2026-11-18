class ProductSpec < ApplicationRecord
  include Deactivatable
  include ScaledAttributes

  # Columns copied by "Duplicate as new". Identity, revision and timestamps are not copied.
  COPYABLE_ATTRIBUTES = %w[
    customer_id width_mm thickness_micron material_type pe silicone silicone_bp antiblock
    core_inches core_orientation reel_limit max_diameter_mm max_reel_g pallet_type reels_per_pallet
    label_inside_core packaging_notes customer_part_no customer_tool_no customer_product_code customer_description
  ].freeze

  belongs_to :customer, optional: true
  has_many :line_rates, dependent: :destroy
  has_many :lines, through: :line_rates

  enum :material_type, { clear: "clear", laminated: "laminated" }, default: :clear, validate: true
  enum :silicone, { none: "none", underside: "underside", reverse: "reverse", both: "both" },
       default: :none, prefix: :silicone, validate: true
  enum :core_orientation, { horizontal: "horizontal", vertical: "vertical" }, default: :horizontal, prefix: :core, validate: true
  enum :reel_limit, { max_diameter: "max_diameter", max_roll_on_side: "max_roll_on_side" }, default: :max_diameter, validate: true
  enum :pallet_type, { euro: "euro", standard: "standard" }, default: :euro, suffix: :pallet, validate: true

  CORE_SIZES = [ 3, 6 ].freeze

  scaled_attribute :silicone_pct, column: :silicone_bp, scale: 100
  scaled_attribute :max_reel_kg, column: :max_reel_g, scale: Weight::GRAMS_PER_KG

  normalizes :code, with: ->(c) { c.strip.upcase }

  validates :code, presence: true
  validates :revision, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :code }
  validates :width_mm, :thickness_micron, numericality: { only_integer: true, greater_than: 0 }
  validates :core_inches, inclusion: { in: CORE_SIZES }
  validates :max_diameter_mm, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :max_diameter_mm, presence: true, if: :max_diameter?
  validates :reels_per_pallet, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :max_reel_g, numericality: { greater_than: 0 }, allow_nil: true
  validates :silicone_bp, presence: true, numericality: { greater_than: 0, less_than_or_equal_to: 10_000 }, unless: :silicone_none?

  # The form hides these fields when they don't apply; drop any stale values.
  before_validation { self.silicone_bp = nil if silicone_none? }
  before_validation { self.max_diameter_mm = nil if max_roll_on_side? }

  scope :by_code, -> { order(:code, :revision) }
  scope :search, ->(q) {
    next all if q.blank?
    like = "%#{sanitize_sql_like(q)}%"
    left_joins(:customer).where(
      "product_specs.code LIKE :q OR product_specs.customer_part_no LIKE :q OR product_specs.customer_product_code LIKE :q " \
      "OR product_specs.customer_description LIKE :q OR customers.name LIKE :q", q: like)
  }

  # A prefilled, unsaved copy for "Duplicate as new". The user gives it a new code.
  def duplicate
    self.class.new(attributes.slice(*COPYABLE_ATTRIBUTES))
  end

  def copy_line_rates_from(source)
    source.line_rates.each { |rate| line_rates.create!(line_id: rate.line_id, kg_per_hour: rate.kg_per_hour) }
  end

  def rate_for(line)
    line_rates.detect { |rate| rate.line_id == line.id }
  end

  # The paper plan writes 250µm as ".250".
  def paper_gauge
    format(".%03d", thickness_micron)
  end

  def to_s
    revision > 1 ? "#{code} rev #{revision}" : code
  end
end
