# Our own company details, from config/company.yml.
module Company
  module_function

  def details
    @details ||= Rails.application.config_for(:company)
  end

  def name = details.fetch(:name)
  def address = Array(details[:address])
  def delivery_address = Array(details[:delivery_address]).presence || address

  def contact_lines
    [ details[:phone], details[:email] ].compact_blank
  end

  def registration_lines
    [ ("VAT no. #{details[:vat_number]}" if details[:vat_number].present?),
      ("Company no. #{details[:company_number]}" if details[:company_number].present?) ].compact
  end

  def po_terms = details[:po_terms]
end
