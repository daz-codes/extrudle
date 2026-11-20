class CreateBackupChecks < ActiveRecord::Migration[8.1]
  def change
    # The result of restoring the latest backup and checking it (Backup::RestoreCheck).
    create_table :backup_checks do |t|
      t.boolean :ok, null: false
      t.text :message, null: false
      t.json :counts, null: false, default: {}
      t.integer :duration_ms
      t.references :requested_by, foreign_key: { to_table: :users }
      t.timestamps
    end
  end
end
