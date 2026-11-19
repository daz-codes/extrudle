# Reads a spreadsheet saved as CSV with Ruby's csv library, plus the things
# Excel needs: its UTF-8 byte order mark, text that isn't valid UTF-8 (older
# Excel saves Windows-1252), and a separator guessed from the header line
# (comma, semicolon or tab, as Excel in some locales saves with semicolons).
# Blank rows are dropped.
#
#   Import::CsvReader.parse("name,currency\r\nBrightform,GBP\r\n") #=> [["name", "currency"], ["Brightform", "GBP"]]
module Import::CsvReader
  class MalformedError < StandardError; end

  SEPARATORS = [ ",", ";", "\t" ].freeze

  module_function

  def parse(text)
    text = normalise(text)
    CSV.parse(text, col_sep: guess_separator(text), row_sep: "\n", nil_value: "")
       .reject { |cells| cells.all? { _1.strip.empty? } }
  rescue CSV::MalformedCSVError => e
    line = e.line_number ? " on line #{e.line_number}" : ""
    raise MalformedError, "The file isn't valid CSV#{line}: check for a \" that isn't closed or a stray \" inside a cell"
  end

  def normalise(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8)
    text = text.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8) unless text.valid_encoding?
    text.delete_prefix("﻿").gsub(/\r\n?/, "\n")
  end

  # The separator used most in the header line, outside quotes.
  def guess_separator(text)
    header = text.lines.first.to_s.gsub(/"[^"]*"/, "")
    SEPARATORS.max_by { header.count(_1) }
  end
end
