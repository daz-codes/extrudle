# Customers, matched by name: new names are added, existing ones updated.
class Import::Customers < Import::Base
  column :name, required: true, aliases: %w[ customer customer_name company ], example: "Brightform Packaging Ltd"
  column :contact_name, label: "Contact", aliases: %w[ contact_name contact_person ], example: "Hannah Cole"
  column :email, aliases: %w[ email_address ], example: "orders@brightform.example"
  column :phone, aliases: %w[ telephone tel phone_number ], example: "0113 496 0000"
  column :address, example: "Unit 9, Leeds LS1 1AA"
  column :currency, example: "GBP", hint: "GBP, EUR or USD. New customers default to GBP."
  column :sage_account_ref, label: "Sage account ref", aliases: %w[ sage_account sage_ref account_ref sage_account_reference ], example: "BRIGHT01"
  column :sage_tax_code, label: "Sage VAT code", aliases: %w[ vat_code tax_code sage_tax_code ], example: "T1"
  column :notes

  def self.description = "Matched by name: new customers are added, existing ones updated."

  private
    def import_row(values)
      name = require_value(values, "name", "Name")
      customer = Customer.where("LOWER(name) = ?", name.downcase).first || Customer.new
      attributes = values.slice("name", "contact_name", "email", "phone", "address", "sage_account_ref", "notes")
      attributes["currency"] = values["currency"].upcase if values["currency"]
      attributes["sage_tax_code"] = values["sage_tax_code"].upcase if values["sage_tax_code"]
      [ name, save_record(customer, attributes) ]
    end
end
