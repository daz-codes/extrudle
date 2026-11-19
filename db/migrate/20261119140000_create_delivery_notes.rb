class CreateDeliveryNotes < ActiveRecord::Migration[8.1]
  def change
    # A batch of delivery notes sent to Sage as one CSV file (kept so it can
    # be downloaded again exactly as sent).
    create_table :sage_exports do |t|
      t.references :created_by, foreign_key: { to_table: :users }
      t.string :filename, null: false
      t.text :csv, null: false
      t.integer :rows_count, null: false, default: 0
      t.timestamps
    end

    # One delivery to a customer, for one sales order.
    create_table :delivery_notes do |t|
      t.string :number, null: false
      t.references :sales_order, null: false, foreign_key: true
      t.string :status, null: false, default: "draft"
      t.date :dispatched_on
      t.references :dispatched_by, foreign_key: { to_table: :users }
      t.string :haulier
      t.string :vehicle_reg
      t.text :delivery_address
      t.text :notes
      t.references :sage_export, foreign_key: true
      t.datetime :exported_at
      t.timestamps
      t.index :number, unique: true
      t.check_constraint "status IN ('draft', 'dispatched')", name: "delivery_notes_status"
      t.check_constraint "status = 'draft' OR dispatched_on IS NOT NULL", name: "delivery_notes_dispatched_on"
    end

    # A pallet (a production log's pallet number) going out on a delivery
    # note. A pallet goes out once.
    create_table :delivery_note_pallets do |t|
      t.references :delivery_note, null: false, foreign_key: true
      t.references :production_run, null: false, foreign_key: true
      t.integer :pallet_no, null: false
      t.timestamps
      t.index %i[ production_run_id pallet_no ], unique: true
      t.check_constraint "pallet_no > 0", name: "delivery_note_pallets_pallet_positive"
    end

    # For the Sage export (PLAN.md §11 Q1 and Q63).
    add_column :customers, :sage_account_ref, :string
    add_column :customers, :sage_tax_code, :string, null: false, default: "T1"
  end
end
