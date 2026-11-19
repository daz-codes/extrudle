class CreateReels < ActiveRecord::Migration[8.1]
  def change
    # Finished reels, one row per line of page 2 of the production log.
    create_table :reels do |t|
      t.references :production_run, null: false, foreign_key: true
      t.integer :reel_no, null: false
      t.datetime :produced_at, null: false
      t.integer :weight_g, null: false
      t.integer :length_m
      t.integer :pallet_no
      t.string :initials
      t.references :user, foreign_key: true
      t.text :note
      t.timestamps

      t.index %i[ production_run_id reel_no ], unique: true
      t.check_constraint "reel_no > 0", name: "reels_reel_no_positive"
      t.check_constraint "weight_g > 0", name: "reels_weight_positive"
      t.check_constraint "length_m IS NULL OR length_m > 0", name: "reels_length_positive"
      t.check_constraint "pallet_no IS NULL OR pallet_no > 0", name: "reels_pallet_positive"
    end

    add_reference :production_runs, :finished_by, foreign_key: { to_table: :users }
  end
end
