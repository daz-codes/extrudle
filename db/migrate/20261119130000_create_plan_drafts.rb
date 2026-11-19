class CreatePlanDrafts < ActiveRecord::Migration[8.1]
  def change
    # A new plan for both lines, prepared while the live plan keeps running.
    # One at a time: `current` is always true and unique.
    create_table :plan_drafts do |t|
      t.references :started_by, foreign_key: { to_table: :users }
      t.boolean :current, null: false, default: true
      t.timestamps
      t.index :current, unique: true
      t.check_constraint "current = 1", name: "plan_drafts_one_at_a_time"
    end

    # Each line's queue start in the draft (the live one is lines.queue_starts_at).
    create_table :plan_draft_lines do |t|
      t.references :plan_draft, null: false, foreign_key: true
      t.references :line, null: false, foreign_key: true
      t.datetime :queue_starts_at
      t.timestamps
      t.index %i[ plan_draft_id line_id ], unique: true
    end

    # Draft blocks belong to a draft (live blocks have none) and remember the
    # live block they were copied from, so publishing updates it in place.
    add_reference :schedule_blocks, :plan_draft, foreign_key: true
    add_reference :schedule_blocks, :source_block, foreign_key: { to_table: :schedule_blocks, on_delete: :nullify }
  end
end
