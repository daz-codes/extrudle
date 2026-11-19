# Suppliers, matched by name: new names are added, existing ones updated.
class Import::Suppliers < Import::Base
  column :name, required: true, aliases: %w[ supplier supplier_name company ], example: "Albion Polymers"
  column :country, example: "United Kingdom"
  column :contact_name, label: "Contact", aliases: %w[ contact_name contact_person ], example: "Sam Price"
  column :email, aliases: %w[ email_address ], example: "sales@albion.example"
  column :phone, aliases: %w[ telephone tel phone_number ], example: "01632 960000"
  column :currency, example: "GBP", hint: "GBP, EUR or USD."
  column :incoterm, aliases: %w[ incoterms default_incoterm ], example: "DAP", hint: "EXW, FCA, FOB, CIF, DAP, DDP…"
  column :notes

  def self.description = "Matched by name: new suppliers are added, existing ones updated."

  private
    def import_row(values)
      name = require_value(values, "name", "Name")
      supplier = Supplier.where("LOWER(name) = ?", name.downcase).first || Supplier.new
      attributes = values.slice("name", "country", "contact_name", "email", "phone", "notes")
      attributes["currency"] = values["currency"].upcase if values["currency"]
      attributes["incoterm"] = values["incoterm"].upcase if values["incoterm"]
      [ name, save_record(supplier, attributes) ]
    end
end
