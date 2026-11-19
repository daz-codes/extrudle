class CreatePurchaseOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :purchase_orders do |t|
      t.string :number, null: false
      t.references :supplier, null: false, foreign_key: true
      t.string :currency, null: false, default: "GBP"
      t.string :incoterm
      t.string :status, null: false, default: "draft"
      t.date :expected_on, null: false
      t.string :supplier_ref
      t.text :notes
      t.datetime :sent_at
      t.timestamps

      t.index :number, unique: true
      t.index %i[ status expected_on ]
    end

    create_table :purchase_order_lines do |t|
      t.references :purchase_order, null: false, foreign_key: true
      t.references :material, null: false, foreign_key: true
      t.integer :quantity_g, null: false
      t.string :quantity_unit, null: false, default: "kg"
      t.integer :price_per_tonne_cents, null: false
      t.timestamps

      t.check_constraint "quantity_g > 0", name: "purchase_order_lines_quantity_positive"
      t.check_constraint "price_per_tonne_cents >= 0", name: "purchase_order_lines_price_non_negative"
    end
  end
end
