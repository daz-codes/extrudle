class CreateCustomers < ActiveRecord::Migration[8.1]
  def change
    create_table :customers do |t|
      t.string :name, null: false
      t.string :contact_name
      t.string :email
      t.string :phone
      t.text :address
      t.text :notes
      t.string :currency, null: false, default: "GBP"
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :customers, :name, unique: true
  end
end
