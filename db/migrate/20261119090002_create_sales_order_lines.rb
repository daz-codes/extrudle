class CreateSalesOrderLines < ActiveRecord::Migration[8.1]
  def change
    create_table :sales_order_lines do |t|
      t.references :sales_order, null: false, foreign_key: true
      t.references :product_spec, null: false, foreign_key: true
      t.integer :quantity_g, null: false
      t.string :customer_batch_no
      t.integer :price_per_tonne_cents

      t.timestamps
    end
    add_check_constraint :sales_order_lines, "quantity_g > 0", name: "sales_order_lines_quantity_positive"
    add_check_constraint :sales_order_lines, "price_per_tonne_cents IS NULL OR price_per_tonne_cents >= 0", name: "sales_order_lines_price_non_negative"
  end
end
