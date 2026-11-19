# A computer (strictly, one browser) approved to use Extrudle (PLAN.md Slice 8a).
# Approving sets a long-lived signed cookie holding a random token; only its
# digest is stored, so a database copy can't be used to forge a computer.
# Every request checks it, so revoking a computer signs it out at once.
#
# Switched on by REQUIRE_APPROVED_COMPUTERS (on for the real deploy, off for
# the demo preview). Working assumption, see PLAN.md §11 Q58.
class Device < ApplicationRecord
  COOKIE = :device_token
  SEEN_EVERY = 5.minutes

  belongs_to :approved_by, class_name: "User", optional: true
  belongs_to :revoked_by, class_name: "User", optional: true

  normalizes :name, with: ->(name) { name.squish }

  validates :name, presence: true, length: { maximum: 60 }
  validates :token_digest, presence: true, uniqueness: true

  scope :approved, -> { where(revoked_at: nil) }
  scope :by_name, -> { order(:name) }

  attr_reader :token

  # Strictly true: an unset config.x key is an empty (truthy) options object.
  def self.required? = Rails.configuration.x.require_approved_computers == true

  def self.digest(token) = OpenSSL::Digest::SHA256.hexdigest(token.to_s)

  # Approves the computer making the request. Returns the device; its #token
  # (only available now) goes in the cookie.
  def self.approve!(name:, approved_by:, user_agent: nil, ip: nil)
    token = SecureRandom.base58(40)
    create!(name:, approved_by:, user_agent:, last_ip: ip, last_used_at: Time.current, token_digest: digest(token))
      .tap { _1.instance_variable_set(:@token, token) }
  end

  def self.find_by_token(token)
    token.present? ? approved.find_by(token_digest: digest(token)) : nil
  end

  def approved? = revoked_at.nil?

  def revoke!(by:)
    update!(revoked_at: Time.current, revoked_by: by)
  end

  # Records the computer being used, at most every few minutes.
  def seen!(ip:)
    return if last_used_at && last_used_at > SEEN_EVERY.ago && last_ip == ip

    update_columns(last_used_at: Time.current, last_ip: ip, updated_at: Time.current)
  end

  def to_s = name
end
