class CreateSalesOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :sales_orders do |t|
      t.string :number, null: false
      t.references :customer, null: false, foreign_key: true
      t.string :customer_po_ref
      t.date :required_on, null: false
      t.boolean :urgent, null: false, default: false
      t.string :status, null: false, default: "open"
      t.text :notes

      t.timestamps
    end
    add_index :sales_orders, :number, unique: true
    add_index :sales_orders, [ :status, :required_on ]
  end
end
