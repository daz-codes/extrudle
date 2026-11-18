class CreateMaterialCategories < ActiveRecord::Migration[8.1]
  def change
    create_table :material_categories do |t|
      t.string :name, null: false
      t.string :description
      t.integer :position, null: false, default: 0

      t.timestamps
    end
    add_index :material_categories, :name, unique: true
  end
end
