# Restores the latest backup every night and checks it (Backup::RestoreCheck).
class BackupRestoreCheckJob < ApplicationJob
  queue_as :default

  def perform
    return unless Backup::RestoreCheck.configured?

    Backup::RestoreCheck.new.call
  end
end
