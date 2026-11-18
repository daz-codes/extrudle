class CreateLineRates < ActiveRecord::Migration[8.1]
  def change
    create_table :line_rates do |t|
      t.references :line, null: false, foreign_key: true
      t.references :product_spec, null: false, foreign_key: true
      t.integer :kg_per_hour, null: false

      t.timestamps
    end
    add_index :line_rates, [ :product_spec_id, :line_id ], unique: true
    add_check_constraint :line_rates, "kg_per_hour > 0", name: "line_rates_kg_per_hour_positive"
  end
end
