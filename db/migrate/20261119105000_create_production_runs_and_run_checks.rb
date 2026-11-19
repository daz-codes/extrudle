class CreateProductionRunsAndRunChecks < ActiveRecord::Migration[8.1]
  def change
    # One production log (paper form 5.4.1.2), identified by its despatch number.
    create_table :production_runs do |t|
      t.integer :despatch_number, null: false
      t.references :line, null: false, foreign_key: true
      t.references :schedule_block, foreign_key: true, index: { unique: true }
      t.references :sales_order_line, null: false, foreign_key: true
      t.references :product_spec, null: false, foreign_key: true
      t.string :status, null: false, default: "running"
      t.datetime :started_at, null: false
      t.datetime :ended_at
      t.references :started_by, foreign_key: { to_table: :users }
      t.string :antiblock_batch_no
      t.string :silicone_batch_no
      t.string :pe_film_batch_no
      t.string :technician_days
      t.string :technician_nights
      t.text :special_instructions
      t.text :comments
      t.timestamps

      t.index :despatch_number, unique: true
      t.index %i[ line_id status ]
      t.check_constraint "despatch_number > 0", name: "production_runs_despatch_number_positive"
      t.check_constraint "ended_at IS NULL OR ended_at >= started_at", name: "production_runs_end_after_start"
    end

    # A yes/no check (prestart, line clearance) or a measurement against its
    # target and tolerance (width, thickness), kept as they were at the time.
    create_table :run_checks do |t|
      t.references :production_run, null: false, foreign_key: true
      t.string :stage, null: false
      t.string :item, null: false
      t.boolean :passed, null: false
      t.integer :target
      t.integer :min_value
      t.integer :max_value
      t.integer :actual
      t.string :unit
      t.references :user, foreign_key: true
      t.datetime :checked_at, null: false
      t.text :note
      t.timestamps

      t.index %i[ production_run_id stage item ]
    end
  end
end
