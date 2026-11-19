# Spreadsheet (CSV) imports for go-live (PLAN.md Slice 9), in the order they
# should be done: suppliers, materials, customers, product specs, opening stock.
#
#   import = Import.for("customers", csv_text)
#   import.preview      # checks every row, saves nothing
#   import.results      # one Import::Base::Result per row
#   import.save         # all or nothing
module Import
  KINDS = {
    "suppliers" => "Import::Suppliers",
    "materials" => "Import::Materials",
    "customers" => "Import::Customers",
    "product_specs" => "Import::ProductSpecs",
    "opening_stock" => "Import::OpeningStock"
  }.freeze

  def self.kind_class(kind) = KINDS.fetch(kind.to_s).constantize

  def self.for(kind, text) = kind_class(kind).new(text)
end
