class CreateScheduleBlocks < ActiveRecord::Migration[8.1]
  def change
    create_table :schedule_blocks do |t|
      t.references :line, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :position, null: false
      t.datetime :starts_at, null: false
      t.datetime :ends_at, null: false
      t.integer :duration_minutes, null: false
      t.references :sales_order_line, foreign_key: true
      t.integer :planned_g
      t.boolean :locked, null: false, default: false
      t.text :notes

      t.timestamps
    end
    add_index :schedule_blocks, [ :line_id, :starts_at ]
    add_index :schedule_blocks, [ :line_id, :position ]
    add_check_constraint :schedule_blocks, "duration_minutes > 0 AND duration_minutes % 30 = 0", name: "schedule_blocks_duration_in_slots"
    add_check_constraint :schedule_blocks, "ends_at > starts_at", name: "schedule_blocks_ends_after_start"
    add_check_constraint :schedule_blocks,
      "kind <> 'job' OR (sales_order_line_id IS NOT NULL AND planned_g > 0)", name: "schedule_blocks_jobs_have_order_line"
  end
end
