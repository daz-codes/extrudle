# lines.queue_starts_at: where each line's queue of unlocked blocks starts. Stored,
# so it only changes when the planner sets it, not as a side effect of other edits.
#
# schedule_blocks.automatic: changeovers the editor adds between jobs for different
# specs. These are rebuilt after every edit; changeovers the planner adds are kept.
class AddQueueStartAndAutomaticChangeovers < ActiveRecord::Migration[8.1]
  def up
    add_column :lines, :queue_starts_at, :datetime
    add_column :schedule_blocks, :automatic, :boolean, null: false, default: false

    execute <<~SQL
      UPDATE lines SET queue_starts_at = (
        SELECT MIN(starts_at) FROM schedule_blocks
        WHERE schedule_blocks.line_id = lines.id AND schedule_blocks.locked = 0
      )
    SQL
    execute "UPDATE schedule_blocks SET automatic = 1 WHERE kind = 'changeover' AND locked = 0"
  end

  def down
    remove_column :schedule_blocks, :automatic
    remove_column :lines, :queue_starts_at
  end
end
