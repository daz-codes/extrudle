class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy

  enum :role, { admin: "admin", office: "office", floor: "floor" }, default: :office, validate: true

  normalizes :email_address, with: ->(e) { e.strip.downcase }
  normalizes :name, with: ->(n) { n.squish }

  validates :name, presence: true
  validates :email_address, presence: true, uniqueness: true
  validates :password, length: { minimum: 8 }, allow_nil: true

  scope :active, -> { where(active: true) }
  scope :by_name, -> { order(:name) }

  # Office and admin users can see the back-office screens; floor users only see /floor.
  def office_access?
    admin? || office?
  end

  def initials
    name.split.map(&:first).join.upcase
  end
end
