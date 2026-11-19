class Material < ApplicationRecord
  include Deactivatable

  belongs_to :material_category
  belongs_to :supplier, optional: true
  has_many :purchase_order_lines, dependent: :restrict_with_error
  has_many :lots, dependent: :restrict_with_error

  enum :origin, { virgin: "virgin", recycled: "recycled" }, default: :virgin, validate: true
  # Regrind is made in-house from edge trim and scrap.
  enum :source, { purchased: "purchased", internal: "internal" }, default: :purchased, validate: true

  normalizes :name, with: ->(n) { n.squish }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validate :internal_materials_have_no_supplier

  scope :by_name, -> { order(:name) }
  scope :search, ->(q) { q.present? ? where("materials.name LIKE :q OR materials.grade LIKE :q", q: "%#{sanitize_sql_like(q)}%") : all }

  def to_s = [ name, grade.presence ].compact.join(" · ")

  private
    def internal_materials_have_no_supplier
      errors.add(:supplier, "must be blank for materials made in-house") if internal? && supplier_id.present?
    end
end
