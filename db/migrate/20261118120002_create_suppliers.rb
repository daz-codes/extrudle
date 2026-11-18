class CreateSuppliers < ActiveRecord::Migration[8.1]
  def change
    create_table :suppliers do |t|
      t.string :name, null: false
      t.string :country
      t.string :contact_name
      t.string :email
      t.string :phone
      t.string :currency, null: false, default: "GBP"
      t.string :incoterm
      t.text :notes
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :suppliers, :name, unique: true
  end
end
