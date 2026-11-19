class Supplier < ApplicationRecord
  include Deactivatable

  has_many :materials, dependent: :restrict_with_error
  has_many :purchase_orders, dependent: :restrict_with_error

  normalizes :name, with: ->(n) { n.squish }
  normalizes :email, with: ->(e) { e.strip.downcase }
  normalizes :incoterm, with: ->(i) { i.strip.upcase.presence }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :currency, inclusion: { in: Currency::CODES }
  validates :incoterm, inclusion: { in: Currency::INCOTERMS }, allow_nil: true

  scope :by_name, -> { order(:name) }
  scope :search, ->(q) { q.present? ? where("name LIKE :q OR country LIKE :q OR contact_name LIKE :q", q: "%#{sanitize_sql_like(q)}%") : all }

  def to_s = name
end
