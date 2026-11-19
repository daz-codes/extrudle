# Dispatched delivery notes sent to Sage as one CSV, kept so it can be
# downloaded again exactly as it was sent.
#
# The file is Sage 50 Accounts' "Audit Trail Transactions" import: one sales
# invoice row (type SI) per order line on each delivery note, valued at the
# order's price per tonne. Working assumption, see PLAN.md §11 Q1 and Q67.
#
#   export = SageExport.create_from!(DeliveryNote.not_exported, user:)
#   export.csv   # the file
class SageExport < ApplicationRecord
  HEADER = [
    "Type", "Account Reference", "Nominal A/C Ref", "Department Code", "Date", "Reference", "Details",
    "Net Amount", "Tax Code", "Tax Amount", "Exchange Rate", "Extra Reference", "User Name", "Project Refn", "Cost Code Refn"
  ].freeze
  DETAILS_LIMIT = 60 # Sage 50's details field

  belongs_to :created_by, class_name: "User", optional: true
  has_many :delivery_notes, dependent: :restrict_with_error

  class NothingToExport < StandardError; end
  # Someone else exported some of the same notes at the same moment.
  class AlreadyExported < StandardError; end

  def self.settings = Rails.application.config_for(:sage)

  def self.tax_codes = settings[:tax_rates_bp].keys.map(&:to_s)

  # Notes ready to go: dispatched, not exported, and with nothing missing.
  def self.ready_notes
    DeliveryNote.not_exported.includes(sales_order: :customer).order(:dispatched_on, :number).select { _1.export_problems.empty? }
  end

  # Exports the notes, marks them exported and their orders invoiced when
  # every note for the order has gone.
  def self.create_from!(notes, user: nil, at: Time.current)
    notes = notes.to_a
    raise NothingToExport, "There's nothing ready to export" if notes.empty?

    rows = notes.flat_map { |note| rows_for(note, user:) }
    transaction do
      export = create!(created_by: user, rows_count: rows.size, csv: to_csv([ HEADER ] + rows),
                       filename: "sage-invoices-#{at.strftime("%Y%m%d-%H%M")}.csv")
      # Only notes still unexported: if another export took any of them first,
      # roll back rather than send the same invoices to Sage twice.
      claimed = DeliveryNote.where(id: notes.map(&:id), exported_at: nil).update_all(exported_at: at, sage_export_id: export.id, updated_at: at)
      raise AlreadyExported, "Some of these delivery notes were exported a moment ago. Check the exports below before trying again." if claimed != notes.size
      notes.map(&:sales_order).uniq.each(&:refresh_invoice_status!)
      export
    end
  end

  def self.rows_for(note, user: nil)
    order, customer = note.sales_order, note.customer
    tax_code = customer.sage_tax_code
    rate_bp = settings[:tax_rates_bp].fetch(tax_code.to_sym) { raise ArgumentError, "Unknown Sage tax code #{tax_code}" }

    note.lines.map do |line|
      net = line.net_cents
      details = "#{order.number} #{line.order_line.product_spec} #{DecimalInput.from_scaled_integer(line.weight_g, Weight::GRAMS_PER_KG)} kg"
      [ "SI", customer.sage_account_ref, settings[:sales_nominal], settings[:department], note.dispatched_on.strftime("%d/%m/%Y"),
        note.number, details.first(DETAILS_LIMIT), amount(net), tax_code, amount((net * rate_bp + 5_000) / 10_000),
        "", order.customer_po_ref.to_s, user&.name.to_s.first(32), "", "" ]
    end
  end

  # "1234.56": two decimals, no thousands separator.
  def self.amount(cents) = DecimalInput.from_scaled_integer(cents, 100, pad: true)

  # RFC 4180: fields with commas, quotes or line breaks are quoted; CRLF line ends.
  def self.to_csv(rows)
    CSV.generate(row_sep: "\r\n", quote_empty: false) { |csv| rows.each { csv << _1 } }
  end
  private_class_method :rows_for, :amount, :to_csv
end
