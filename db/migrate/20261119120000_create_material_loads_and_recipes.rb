class CreateMaterialLoadsAndRecipes < ActiveRecord::Migration[8.1]
  FEEDS = %w[ virgin_coex virgin_mainex pcw regrind ].freeze

  def change
    # A spec's recipe: the share of each feed, in basis points (10000 = 100%).
    create_table :spec_ingredients do |t|
      t.references :product_spec, null: false, foreign_key: true
      t.string :feed, null: false
      t.integer :share_bp, null: false
      t.timestamps
      t.index %i[ product_spec_id feed ], unique: true
      t.check_constraint "share_bp BETWEEN 0 AND 10000", name: "spec_ingredients_share_range"
      t.check_constraint "feed IN (#{FEEDS.map { "'#{_1}'" }.join(", ")})", name: "spec_ingredients_feed"
    end

    # A bag going on a feed of a production log, from a reel number onwards.
    create_table :material_loads do |t|
      t.references :production_run, null: false, foreign_key: true
      t.references :lot, null: false, foreign_key: true
      t.string :feed, null: false
      t.integer :from_reel_no, null: false
      t.datetime :loaded_at, null: false
      t.boolean :carried_over, null: false, default: false
      # This load marked the bag it replaced empty (undone if the load is removed).
      t.boolean :marked_previous_empty, null: false, default: false
      t.string :initials
      t.references :user, foreign_key: true
      t.text :note
      t.timestamps
      t.index %i[ production_run_id feed from_reel_no ]
      t.check_constraint "from_reel_no > 0", name: "material_loads_from_reel_positive"
      t.check_constraint "feed IN (#{FEEDS.map { "'#{_1}'" }.join(", ")})", name: "material_loads_feed"
    end

    # Material used by a run is an issue_to_production movement against the run.
    add_reference :stock_movements, :production_run, foreign_key: true
    # The adjustment that zeroes a bag marked empty: its variance (Stock::Reconciliation).
    add_column :stock_movements, :bag_variance, :boolean, null: false, default: false

    # A bag marked empty is reconciled once every run that used it has finished.
    add_column :lots, :emptied_at, :datetime
    add_column :lots, :reconciled_at, :datetime
  end
end
