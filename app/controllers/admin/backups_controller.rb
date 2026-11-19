# Users › Backups: whether Litestream is streaming to R2, and the last restore
# checks. "Check now" restores the latest backup and checks it straight away.
class Admin::BackupsController < ApplicationController
  require_role :admin

  def show
    @configured = Backup::RestoreCheck.configured?
    @checks = BackupCheck.includes(:requested_by).recent_first.limit(14)
  end

  def create
    unless Backup::RestoreCheck.configured?
      return redirect_to admin_backups_path, alert: "Backups aren't set up on this server, so there's nothing to check."
    end

    check = Backup::RestoreCheck.new.call(requested_by: Current.user)
    if check.ok?
      redirect_to admin_backups_path, notice: check.message
    else
      redirect_to admin_backups_path, alert: check.message
    end
  end
end
