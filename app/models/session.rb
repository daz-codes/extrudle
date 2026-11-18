class Session < ApplicationRecord
  belongs_to :user

  # Sessions of deactivated users never authenticate, wherever they come from.
  scope :for_active_users, -> { joins(:user).merge(User.active) }
end
