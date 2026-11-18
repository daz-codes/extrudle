require "test_helper"

class MasterDataCrudTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:office) }

  test "suppliers: new, create, edit, update" do
    get new_supplier_path
    assert_response :success

    assert_difference "Supplier.count" do
      post suppliers_path, params: { supplier: { name: "Nordic Resin AB", country: "Sweden", currency: "EUR", incoterm: "FCA" } }
    end
    assert_redirected_to suppliers_path

    supplier = Supplier.find_by!(name: "Nordic Resin AB")
    get edit_supplier_path(supplier)
    assert_response :success

    patch supplier_path(supplier), params: { supplier: { incoterm: "BAD" } }
    assert_response :unprocessable_content
  end

  test "material categories: create and update" do
    assert_difference "MaterialCategory.count" do
      post material_categories_path, params: { material_category: { name: "Colour", position: 6 } }
    end
    patch material_category_path(material_categories(:virgin)), params: { material_category: { description: "Main-Ex" } }
    assert_equal "Main-Ex", material_categories(:virgin).reload.description
  end

  test "materials: create, filter by category, reject a supplier on regrind" do
    assert_difference "Material.count" do
      post materials_path, params: { material: { name: "Tint", material_category_id: material_categories(:virgin).id,
                                                 supplier_id: suppliers(:albion).id, origin: "virgin", source: "purchased" } }
    end

    get materials_path(category: material_categories(:recycled).id)
    assert_select "a", text: "Regrind chip"
    assert_select "a", text: "JADE", count: 0

    patch material_path(materials(:regrind)), params: { material: { supplier_id: suppliers(:albion).id } }
    assert_response :unprocessable_content
  end

  test "lines: create and update" do
    assert_difference "Line.count" do
      post lines_path, params: { line: { name: "d3", default_changeover_minutes: 60, position: 3 } }
    end
    assert Line.exists?(name: "D3")

    patch line_path(lines(:d1)), params: { line: { default_changeover_minutes: 45 } }
    assert_equal 45, lines(:d1).reload.default_changeover_minutes
  end
end
