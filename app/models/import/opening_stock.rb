# Stock on site at go-live, one row per material and batch (PLAN.md §11 Q32):
# each row is received like "Add stock without a PO", split evenly across its
# bags, each with its own lot code and label. Every row adds stock, so import
# a file once.
class Import::OpeningStock < Import::Base
  column :material, required: true, aliases: %w[ material_name ], example: "JADE"
  column :quantity_kg, label: "Total kg", required: true, aliases: %w[ quantity kg weight weight_kg total_kg total_weight ], example: "5500"
  column :bags, aliases: %w[ bag_count number_of_bags ], example: "5", hint: "Defaults to 1."
  column :supplier_lot_ref, label: "Supplier batch", aliases: %w[ batch batch_no supplier_batch lot_ref ], example: "CZ302-26-118"
  column :first_bag_no, label: "First bag no", aliases: %w[ bag_no bag first_bag ], example: "939"
  column :location, example: "On site", hint: "On site, Storage, At supplier or In transit."
  column :received_on, label: "Received", aliases: %w[ date received_date ], example: "01/11/2026", hint: "Defaults to today."
  column :notes, example: "Opening stock count"

  def self.description = "Every row adds new lots. Import each file once; check the preview first."

  private
    def import_row(values)
      material = find_by_name(Material, require_value(values, "material", "Material"), "material")
      # Every row adds new lots, so the same batch already in stock usually means the file was imported before.
      # (Rows earlier in this file don't count: they're in the same rolled-back preview.)
      batch = [ material.id, values["supplier_lot_ref"] ]
      if batch.last && (@batches_in_file ||= Set.new).add?(batch) && material.lots.exists?(supplier_lot_ref: batch.last)
        warn_about_row "#{material.name} batch #{values["supplier_lot_ref"]} is already in stock. Has this file been imported before?"
      end
      receipt = Stock::Receipt.new(
        material_id: material.id, quantity: require_value(values, "quantity_kg", "Total kg"), quantity_unit: "kg",
        bags: values["bags"] || 1, supplier_lot_ref: values["supplier_lot_ref"], first_bag_no: values["first_bag_no"],
        location: values["location"] ? choice(values["location"], Lot::LOCATIONS.keys, "Location") : "on_site",
        received_on: values["received_on"] ? date(values["received_on"], "Received") : Date.current,
        notes: values["notes"] || "Opening stock"
      )
      raise RowError, receipt.errors.full_messages.to_sentence unless receipt.save

      [ "#{material.name}: #{receipt.lots.size} × #{receipt.lots.first.code}…", :created ]
    end
end
