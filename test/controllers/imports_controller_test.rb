require "test_helper"

class ImportsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:office) }

  def upload(text)
    Rack::Test::UploadedFile.new(StringIO.new(text), "text/csv", original_filename: "customers.csv")
  end

  test "lists the imports in order and offers a template" do
    get imports_path
    assert_select "a[href=?]", import_path("product_specs")
    get import_path("customers")
    assert_select "td", /Sage account ref/
    get template_import_path("customers", format: :csv)
    assert_equal "text/csv", response.media_type
    assert response.body.start_with?("Name,Contact,")
  end

  test "upload, check, then import" do
    post preview_import_path("customers"), params: { file: upload("Name,Currency\nUploaded Ltd,GBP\n") }
    assert_response :success
    assert_select "#line_2", /Uploaded Ltd.*Created/m
    assert_not Customer.exists?(name: "Uploaded Ltd")

    post run_import_path("customers"), params: { csv: "Name,Currency\nUploaded Ltd,GBP\n" }
    assert_redirected_to import_path("customers")
    assert_equal "Imported customers: 1 created.", flash[:notice]
    assert Customer.exists?(name: "Uploaded Ltd")
  end

  test "a file with problems shows them and offers no import button" do
    post preview_import_path("customers"), params: { file: upload("Name,Currency\nBad Ltd,XYZ\n") }
    assert_select "#line_2", /Currency/
    assert_select "input[type=submit][value^=Import]", count: 0
  end

  test "an unknown kind and floor users are turned away" do
    get import_path("nonsense")
    assert_redirected_to imports_path
    sign_in_as users(:floor)
    get imports_path
    assert_redirected_to floor_root_path
  end
end
