require "test_helper"

class ProductSpecsControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:office) }

  def spec_params(**overrides)
    { code: "KF-900-450", width_mm: "900", thickness_micron: "450", material_type: "clear", silicone: "none",
      core_inches: "6", core_orientation: "horizontal", reel_limit: "max_diameter", max_diameter_mm: "1000",
      max_reel_kg: "1,100", pallet_type: "euro" }.merge(overrides)
  end

  test "show mirrors the production plan and lists line rates" do
    get product_spec_path(product_specs(:bf_700))
    assert_response :success
    assert_select "td", text: ".250"
    assert_select "input[name='line_rate[kg_per_hour]'][value='190']"
  end

  test "create stores grams and basis points" do
    assert_difference "ProductSpec.count" do
      post product_specs_path, params: { product_spec: spec_params(silicone: "underside", silicone_pct: "0.5") }
    end
    spec = ProductSpec.find_by!(code: "KF-900-450")
    assert_redirected_to product_spec_path(spec)
    assert_equal 1_100_000, spec.max_reel_g
    assert_equal 50, spec.silicone_bp
  end

  test "create with bad input re-renders with errors" do
    post product_specs_path, params: { product_spec: spec_params(width_mm: "", max_reel_kg: "lots") }
    assert_response :unprocessable_content
    assert_select "#product_spec_max_reel_kg_error", /not a number/
  end

  test "duplicate as new prefills the form and copies line rates" do
    source = product_specs(:bf_700)
    get new_product_spec_path(copy_from: source)
    assert_response :success
    assert_select "input[name='product_spec[width_mm]'][value='700']"
    assert_select "input[name='product_spec[code]']:not([value])"

    post product_specs_path, params: { copy_from: source.id, product_spec: spec_params(code: "BF-700-250-B", width_mm: "700") }
    copy = ProductSpec.find_by!(code: "BF-700-250-B")
    assert_equal [ 175, 190 ], copy.line_rates.map(&:kg_per_hour).sort
  end

  test "errors on stored columns show inline next to the form field" do
    post product_specs_path, params: { product_spec: spec_params(silicone: "underside", silicone_pct: "0", max_reel_kg: "-5") }
    assert_response :unprocessable_content
    assert_select "#product_spec_silicone_pct_error", /must be greater than 0/
    assert_select "input#product_spec_silicone_pct[aria-invalid=true]"
    assert_select "#product_spec_max_reel_kg_error", /must be greater than 0/
  end

  test "a taken code is reported on the code field" do
    post product_specs_path, params: { product_spec: spec_params(code: "bf-700-250") }
    assert_response :unprocessable_content
    assert_select "#product_spec_code_error", /already used by another spec/
  end

  test "show lists an inactive line that still has a rate" do
    lines(:d2).update!(active: false)
    get product_spec_path(product_specs(:bf_700))
    assert_select "input[name='line_rate[kg_per_hour]'][value='175']"
  end

  test "editing a used spec creates the next revision" do
    spec = product_specs(:bf_700)
    get edit_product_spec_path(spec)
    assert_select "p", /creates\s+revision 2/

    assert_difference "ProductSpec.count" do
      patch product_spec_path(spec), params: { product_spec: { width_mm: "710" } }
    end
    revision = ProductSpec.find_by!(code: "BF-700-250", revision: 2)
    assert_redirected_to product_spec_path(revision)
    follow_redirect!
    assert_select "#notice", /revision 2/
  end

  test "update" do
    patch product_spec_path(product_specs(:stock)), params: { product_spec: { reels_per_pallet: "2" } }
    assert_redirected_to product_spec_path(product_specs(:stock))
    assert_equal 2, product_specs(:stock).reload.reels_per_pallet
  end
end
