class CreateProductSpecs < ActiveRecord::Migration[8.1]
  def change
    create_table :product_specs do |t|
      t.string :code, null: false
      t.integer :revision, null: false, default: 1
      t.references :customer, foreign_key: true

      t.integer :width_mm, null: false
      t.integer :thickness_micron, null: false
      t.string :material_type, null: false, default: "clear"
      t.boolean :pe, null: false, default: false
      t.string :silicone, null: false, default: "none"
      t.integer :silicone_bp
      t.boolean :antiblock, null: false, default: false

      t.integer :core_inches, null: false, default: 6
      t.string :core_orientation, null: false, default: "horizontal"
      t.string :reel_limit, null: false, default: "max_diameter"
      t.integer :max_diameter_mm
      t.integer :max_reel_g

      t.string :pallet_type, null: false, default: "euro"
      t.integer :reels_per_pallet
      t.boolean :label_inside_core, null: false, default: false
      t.text :packaging_notes

      t.string :customer_part_no
      t.string :customer_tool_no
      t.string :customer_product_code
      t.string :customer_description

      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :product_specs, [ :code, :revision ], unique: true
    add_check_constraint :product_specs, "width_mm > 0", name: "product_specs_width_positive"
    add_check_constraint :product_specs, "thickness_micron > 0", name: "product_specs_thickness_positive"
    add_check_constraint :product_specs, "revision > 0", name: "product_specs_revision_positive"
  end
end
