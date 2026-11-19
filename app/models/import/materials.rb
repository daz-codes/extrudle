# Materials, matched by name. The category must exist; the supplier, if given, too.
class Import::Materials < Import::Base
  column :name, required: true, aliases: %w[ material material_name ], example: "JADE"
  column :category, required: true, aliases: %w[ material_category ], example: "Virgin polymer"
  column :supplier, aliases: %w[ supplier_name ], example: "Pacific Resin Exports"
  column :grade, example: "CZ-302"
  column :origin, example: "Virgin", hint: "Virgin or Recycled."
  column :source, example: "Purchased", hint: "Purchased, or Internal for regrind made here."
  column :notes

  def self.description = "Matched by name. Categories and suppliers must already exist (import suppliers first)."

  private
    def import_row(values)
      name = require_value(values, "name", "Name")
      material = Material.where("LOWER(name) = ?", name.downcase).first || Material.new
      attributes = values.slice("name", "grade", "notes")
      attributes["material_category"] = find_by_name(MaterialCategory, values["category"], "material category") if values["category"]
      attributes["supplier"] = find_by_name(Supplier, values["supplier"], "supplier") if values["supplier"]
      attributes["origin"] = choice(values["origin"], Material.origins.keys, "Origin") if values["origin"]
      attributes["source"] = choice(values["source"], Material.sources.keys, "Source") if values["source"]
      [ name, save_record(material, attributes) ]
    end
end
