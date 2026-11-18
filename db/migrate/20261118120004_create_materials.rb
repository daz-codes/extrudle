class CreateMaterials < ActiveRecord::Migration[8.1]
  def change
    create_table :materials do |t|
      t.string :name, null: false
      t.references :material_category, null: false, foreign_key: true
      t.references :supplier, foreign_key: true
      t.string :grade
      t.string :origin, null: false, default: "virgin"
      t.string :source, null: false, default: "purchased"
      t.text :notes
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :materials, :name, unique: true
  end
end
