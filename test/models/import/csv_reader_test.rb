require "test_helper"

class Import::CsvReaderTest < ActiveSupport::TestCase
  def parse(text) = Import::CsvReader.parse(text)

  test "reads plain rows with CRLF or LF line ends" do
    assert_equal [ %w[ a b ], %w[ 1 2 ] ], parse("a,b\r\n1,2\r\n")
    assert_equal [ %w[ a b ], %w[ 1 2 ] ], parse("a,b\n1,2")
  end

  test "quoted fields hold separators, doubled quotes and line breaks" do
    text = %(name,address\r\n"Brightform, Ltd","Unit 4\r\nLeeds"\r\n"6"" core",x\r\n)
    assert_equal [ %w[ name address ], [ "Brightform, Ltd", "Unit 4\nLeeds" ], [ "6\" core", "x" ] ], parse(text)
  end

  test "keeps empty fields and skips blank lines" do
    assert_equal [ %w[ a b c ], [ "1", "", "3" ] ], parse("a,b,c\n\n1,,3\n,,\n")
  end

  test "Excel's byte order mark, semicolons and tabs" do
    assert_equal [ %w[ name currency ], %w[ Rhine EUR ] ], parse("\uFEFFname;currency\nRhine;EUR\n")
    assert_equal [ %w[ name grade ], [ "JADE", "CZ-302" ] ], parse("name\tgrade\nJADE\tCZ-302\n")
  end

  test "Windows-1252 text from older Excel" do
    assert_equal [ [ "price" ], [ "£1650" ] ], parse("price\n\xA31650\n".b)
  end

  test "an unclosed quote is an error" do
    error = assert_raises(Import::CsvReader::MalformedError) { parse(%(a,b\n"oops,1\n)) }
    assert_match "isn't valid CSV", error.message
  end

  test "a semicolon file keeps commas inside cells" do
    assert_equal [ %w[ name address ], [ "Rhine", "Industriestraße 12, Ludwigshafen" ] ], parse("name;address\nRhine;Industriestraße 12, Ludwigshafen\n")
  end
end
