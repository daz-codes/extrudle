# One run of the restore check: the latest backup was restored and checked.
class BackupCheck < ApplicationRecord
  belongs_to :requested_by, class_name: "User", optional: true

  scope :recent_first, -> { order(created_at: :desc, id: :desc) }

  def self.latest = recent_first.first
end
