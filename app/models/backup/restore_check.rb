# Proves the backups work (PLAN.md Slice 9): restores the latest Litestream
# backup from R2 to a temporary file, then checks it with SQLite's integrity
# check and counts the rows in the tables that matter, next to the live
# counts. Runs every night (config/recurring.yml) and from Users › Backups.
# The result is kept as a BackupCheck. bin/backup-drill does the same locally.
class Backup::RestoreCheck
  DATABASE = "/rails/storage/production.sqlite3"
  CONFIG = Rails.root.join("config/litestream.yml").to_s
  TABLES = %w[ users customers product_specs sales_orders schedule_blocks lots stock_movements production_runs reels delivery_notes ].freeze
  # A backup is at most a few seconds behind; anything older than this missing is a problem.
  ALLOWED_GAP = 25

  # runner: (command array) -> [output, success]. Swapped in tests.
  def initialize(runner: method(:run_command))
    @runner = runner
  end

  def self.configured? = ENV["LITESTREAM_BUCKET"].present? && system("which litestream > /dev/null 2>&1")

  def call(requested_by: nil)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    ok, message, counts = check
    BackupCheck.create!(ok:, message:, counts:, requested_by:,
                        duration_ms: ((Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000).round)
  end

  private
    def check
      Dir.mktmpdir("restore-check") do |dir|
        restored = File.join(dir, "restored.sqlite3")
        output, success = @runner.call([ "litestream", "restore", "-config", CONFIG, "-o", restored, DATABASE ])
        return [ false, "The restore failed: #{output.to_s.lines.last(3).join.strip.presence || "no output"}", {} ] unless success && File.exist?(restored)

        db = SQLite3::Database.new(restored, readonly: true)
        integrity = db.get_first_value("PRAGMA integrity_check")
        return [ false, "The restored database failed SQLite's integrity check: #{integrity}", {} ] unless integrity == "ok"

        counts = TABLES.to_h { |table| [ table, { "restored" => count(db, table), "live" => live_count(table) } ] }
        short = counts.select { |_, c| c["restored"].nil? || c["restored"] < c["live"] - ALLOWED_GAP }
        if short.any?
          [ false, "The restored copy is missing rows in #{short.keys.to_sentence}", counts ]
        else
          [ true, "Restored the latest backup and checked it: #{counts.sum { _2["restored"] }} rows across #{TABLES.size} tables", counts ]
        end
      rescue SQLite3::Exception => e
        [ false, "The restored file isn't a usable database: #{e.message}", {} ]
      ensure
        db&.close
      end
    end

    # nil if the table is missing from the backup.
    def count(db, table)
      db.get_first_value("SELECT COUNT(*) FROM #{table}")
    rescue SQLite3::Exception
      nil
    end

    def live_count(table) = ActiveRecord::Base.connection.select_value(Arel::Table.new(table).project(Arel.star.count))

    def run_command(command)
      output, status = Open3.capture2e(*command)
      [ output, status.success? ]
    end
end
