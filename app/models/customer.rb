class Customer < ApplicationRecord
  include Deactivatable

  has_many :product_specs, dependent: :restrict_with_error
  has_many :sales_orders, dependent: :restrict_with_error

  normalizes :name, with: ->(n) { n.squish }
  normalizes :email, with: ->(e) { e.strip.downcase }
  normalizes :sage_account_ref, with: ->(ref) { ref.strip.upcase.presence }

  validates :name, presence: true, uniqueness: { case_sensitive: false }
  validates :currency, inclusion: { in: Currency::CODES }
  # Sage 50 account references are up to 8 characters.
  validates :sage_account_ref, length: { maximum: 8 }, uniqueness: { case_sensitive: false }, allow_nil: true
  # Default planner bar colour for this customer's jobs (JobColour); nil keeps lime/lemon.
  normalizes :colour, with: ->(c) { c.strip.presence }
  validates :colour, inclusion: { in: JobColour::NAMES }, allow_nil: true
  validates :sage_tax_code, inclusion: { in: ->(_) { SageExport.tax_codes } }

  scope :by_name, -> { order(:name) }
  scope :search, ->(q) { q.present? ? where("name LIKE :q OR contact_name LIKE :q", q: "%#{sanitize_sql_like(q)}%") : all }

  def to_s = name
end
