# Shared by the Prawn documents in app/pdfs: colours, text that Helvetica can
# print, and exact weights and dates.
module PdfFormatting
  include ActionView::Helpers::NumberHelper

  INK = "18181B"
  MUTED = "52525B"
  RULE = "D4D4D8"
  FILL = "F4F4F5"
  OK = "047857"
  BAD = "B91C1C"

  private
    def date(value) = value ? value.strftime("%-d %b %Y") : "—"

    def date_time(value) = value ? value.in_time_zone.strftime("%-d %b %Y %H:%M") : "—"

    # Exact, never rounded: "12.345 t", "750 kg".
    def quantity(grams, unit = nil)
      unit ||= grams >= Weight::GRAMS_PER_TONNE ? "t" : "kg"
      "#{number_with_delimiter(DecimalInput.from_scaled_integer(grams, EnteredQuantity::UNITS.fetch(unit)))} #{unit}"
    end

    # Always in kg, for columns of weights: "1,042.5".
    def kg_number(grams) = number_with_delimiter(DecimalInput.from_scaled_integer(grams, Weight::GRAMS_PER_KG))

    # Keeps Windows-1252 characters (£, €, µ, é…) and transliterates the rest.
    def text(string)
      string.to_s.each_char.map do |char|
        char.encode(Encoding::Windows_1252)
        char
      rescue EncodingError
        I18n.transliterate(char)
      end.join
    end
end
