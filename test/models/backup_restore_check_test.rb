require "test_helper"

class BackupRestoreCheckTest < ActiveSupport::TestCase
  # Stands in for `litestream restore`: writes a database to the -o path.
  def fake_restore(rows: nil, success: true, integrity_ok: true)
    lambda do |command|
      path = command[command.index("-o") + 1]
      if success
        db = SQLite3::Database.new(path)
        Backup::RestoreCheck::TABLES.each do |table|
          db.execute("CREATE TABLE #{table} (id INTEGER)")
          (rows || ActiveRecord::Base.connection.select_value("SELECT COUNT(*) FROM #{table}")).times { db.execute("INSERT INTO #{table} VALUES (1)") }
        end
        db.close
        File.write(path, "not a database") unless integrity_ok
      end
      [ success ? "restored" : "no generations found", success ]
    end
  end

  test "a good restore passes and records the counts" do
    check = Backup::RestoreCheck.new(runner: fake_restore).call(requested_by: users(:admin))
    assert check.ok?, check.message
    assert_match "Restored the latest backup and checked it", check.message
    assert_equal User.count, check.counts.dig("users", "restored")
    assert_equal users(:admin), check.requested_by
  end

  test "a failed restore, a corrupt file or missing rows fail the check" do
    assert_match "The restore failed: no generations found", Backup::RestoreCheck.new(runner: fake_restore(success: false)).call.message

    corrupt = Backup::RestoreCheck.new(runner: fake_restore(integrity_ok: false)).call
    assert_not corrupt.ok?

    40.times { |n| Customer.create!(name: "Extra #{n}") }
    short = Backup::RestoreCheck.new(runner: fake_restore(rows: 0)).call
    assert_not short.ok?
    assert_match "missing rows in", short.message
  end

  test "the nightly job does nothing where backups aren't set up" do
    assert_no_difference -> { BackupCheck.count } do
      BackupRestoreCheckJob.perform_now
    end
  end
end
