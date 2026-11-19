# Reads a spreadsheet saved as CSV (RFC 4180): quoted fields, "" for a quote,
# line breaks inside quotes, CRLF or LF, and Excel's UTF-8 byte order mark.
# The separator is guessed from the header line (comma, semicolon or tab), as
# Excel in some locales saves with semicolons. Text that isn't valid UTF-8 is
# read as Windows-1252, which is what older Excel saves.
#
# Written by hand because the csv gem isn't in the bundle (CLAUDE.md: no extra gems).
#
#   Import::CsvReader.parse("name,currency\r\nBrightform,GBP\r\n") #=> [["name", "currency"], ["Brightform", "GBP"]]
module Import::CsvReader
  class MalformedError < StandardError; end

  SEPARATORS = [ ",", ";", "\t" ].freeze

  module_function

  def parse(text)
    text = normalise(text)
    separator = guess_separator(text)
    rows = []
    row = []
    field = +""
    quoted = false
    index = 0

    while index < text.length
      char = text[index]
      if quoted
        if char == '"' && text[index + 1] == '"'
          field << '"'
          index += 1
        elsif char == '"'
          quoted = false
        else
          field << char
        end
      elsif char == '"' && field.empty?
        quoted = true
      elsif char == separator
        row << field
        field = +""
      elsif char == "\n"
        rows << (row << field)
        row = []
        field = +""
      else
        field << char
      end
      index += 1
    end

    raise MalformedError, "A quoted field isn't closed (a \" is missing)" if quoted

    rows << (row << field) unless row.empty? && field.empty?
    rows.reject { |cells| cells.all? { _1.strip.empty? } }
  end

  def normalise(text)
    text = text.to_s.dup.force_encoding(Encoding::UTF_8)
    text = text.force_encoding(Encoding::Windows_1252).encode(Encoding::UTF_8) unless text.valid_encoding?
    text.delete_prefix("\uFEFF").gsub(/\r\n?/, "\n")
  end

  # The separator used most in the header line, outside quotes.
  def guess_separator(text)
    header = text.lines.first.to_s.gsub(/"[^"]*"/, "")
    SEPARATORS.max_by { header.count(_1) }
  end
end
