class CreateLotsAndStockMovements < ActiveRecord::Migration[8.1]
  def change
    create_table :lots do |t|
      t.string :code, null: false
      t.references :material, null: false, foreign_key: true
      t.references :purchase_order_line, foreign_key: true
      t.string :supplier_lot_ref
      t.string :bag_no
      t.string :delivery_ref
      t.string :location, null: false, default: "on_site"
      t.date :received_on, null: false
      t.integer :initial_g, null: false
      t.text :notes
      t.timestamps

      t.index :code, unique: true
      t.index %i[ material_id location ]
      t.check_constraint "initial_g > 0", name: "lots_initial_positive"
    end

    create_table :stock_movements do |t|
      t.references :lot, null: false, foreign_key: true
      t.string :kind, null: false
      t.integer :quantity_g, null: false
      t.string :from_location
      t.string :to_location
      t.references :user, foreign_key: true
      t.text :note
      t.datetime :moved_at, null: false
      t.timestamps

      t.index %i[ lot_id moved_at ]
      # Transfers move a whole lot and change no weight; everything else changes weight.
      t.check_constraint "(kind = 'transfer') = (quantity_g = 0)", name: "stock_movements_weight_matches_kind"
    end

    add_column :purchase_orders, :closed_short_at, :datetime
  end
end
