class CreateLines < ActiveRecord::Migration[8.1]
  def change
    create_table :lines do |t|
      t.string :name, null: false
      t.string :machine_no
      t.integer :default_changeover_minutes, null: false, default: 60
      t.integer :position, null: false, default: 0
      t.boolean :active, null: false, default: true

      t.timestamps
    end
    add_index :lines, :name, unique: true
    add_check_constraint :lines, "default_changeover_minutes >= 0", name: "lines_changeover_non_negative"
  end
end
