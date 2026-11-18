class Customer < ApplicationRecord
  include Deactivatable

  has_many :product_specs, dependent: :restrict_with_error
  has_many :sales_orders, dependent: :restrict_with_error

  normalizes :name, with: ->(n) { n.squish }
  normalizes :email, with: ->(e) { e.strip.downcase }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :currency, inclusion: { in: Currency::CODES }

  scope :by_name, -> { order(:name) }
  scope :search, ->(q) { q.present? ? where("name LIKE :q OR contact_name LIKE :q", q: "%#{sanitize_sql_like(q)}%") : all }

  def to_s = name
end
