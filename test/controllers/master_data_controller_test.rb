require "test_helper"

class MasterDataControllerTest < ActionDispatch::IntegrationTest
  INDEXES = %i[ master_data_path customers_path suppliers_path material_categories_path materials_path lines_path product_specs_path ]

  test "office and admin users can open every master data page" do
    %i[ office admin ].each do |name|
      sign_in_as users(name)
      INDEXES.each do |path|
        get public_send(path)
        assert_response :success, "#{name} → #{path}"
      end
      sign_out
    end
  end

  test "floor users are kept out" do
    sign_in_as users(:floor)
    INDEXES.each do |path|
      get public_send(path)
      assert_redirected_to floor_root_path
    end
  end

  test "index pages hide inactive records unless asked" do
    sign_in_as users(:office)
    get customers_path
    assert_select "td", text: "Dormant Trays Ltd", count: 0

    get customers_path(inactive: "1")
    assert_select "a", text: "Dormant Trays Ltd"
  end

  test "index search" do
    sign_in_as users(:office)
    get customers_path(q: "rhine")
    assert_select "a", text: "Rhine Valley Verpackung GmbH"
    assert_select "a", text: "Brightform Packaging Ltd", count: 0
  end
end
