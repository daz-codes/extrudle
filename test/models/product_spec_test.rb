require "test_helper"

class ProductSpecTest < ActiveSupport::TestCase
  def valid_spec(**attrs)
    ProductSpec.new({ code: "new-1", width_mm: 600, thickness_micron: 300, max_diameter_mm: 800 }.merge(attrs))
  end

  test "valid with the essentials and normalises the code" do
    spec = valid_spec
    assert spec.valid?, spec.errors.full_messages.to_sentence
    assert_equal "NEW-1", spec.code
    assert spec.clear?
    assert spec.silicone_none?
  end

  test "code and revision are unique together" do
    duplicate = valid_spec(code: "bf-700-250", revision: 1)
    assert_not duplicate.valid?
    assert duplicate.errors.of_kind?(:revision, :taken)

    assert valid_spec(code: "BF-700-250", revision: 2).valid?
  end

  test "width and thickness must be positive whole numbers" do
    spec = valid_spec(width_mm: 0, thickness_micron: -5)
    assert_not spec.valid?
    assert spec.errors.include?(:width_mm)
    assert spec.errors.include?(:thickness_micron)
  end

  test "core must be 3 or 6 inch" do
    assert_not valid_spec(core_inches: 4).valid?
  end

  test "silicone needs a percentage, stored in basis points" do
    spec = valid_spec(silicone: "underside")
    assert_not spec.valid?
    assert spec.errors.include?(:silicone_bp)

    spec.silicone_pct = "0.55"
    assert spec.valid?
    assert_equal 55, spec.silicone_bp
    assert_equal "0.55", spec.silicone_pct
  end

  test "choosing no silicone clears a stale percentage" do
    spec = valid_spec(silicone: "none", silicone_pct: "0.5")
    assert spec.valid?
    assert_nil spec.silicone_bp
  end

  test "max reel weight is entered in kg and stored in grams" do
    spec = valid_spec(max_reel_kg: "1,100.5")
    assert_equal 1_100_500, spec.max_reel_g
    assert_equal "1100.5", spec.max_reel_kg
  end

  test "bad numbers become validation errors, not exceptions" do
    spec = valid_spec(max_reel_kg: "heavy", silicone: "both", silicone_pct: "lots")
    assert_not spec.valid?
    assert spec.errors.of_kind?(:max_reel_kg, :not_a_number)
    assert spec.errors.of_kind?(:silicone_pct, :not_a_number)
    assert_equal "heavy", spec.max_reel_kg
  end

  test "a European decimal comma is rejected rather than read as thousands" do
    spec = valid_spec(max_reel_kg: "1,5")
    assert_not spec.valid?
    assert spec.errors.of_kind?(:max_reel_kg, :not_a_number)
    assert_nil spec.max_reel_g
  end

  test "max diameter is required for a diameter limit and dropped for max roll on side" do
    assert_not valid_spec(max_diameter_mm: nil).valid?

    spec = valid_spec(reel_limit: "max_roll_on_side", max_diameter_mm: 900)
    assert spec.valid?
    assert_nil spec.max_diameter_mm
  end

  test "paper gauge matches the production plan" do
    assert_equal ".250", product_specs(:bf_700).paper_gauge
    assert_equal ".050", valid_spec(thickness_micron: 50).paper_gauge
  end

  test "duplicate copies the spec but not its identity" do
    source = product_specs(:bf_700)
    copy = source.duplicate

    assert copy.new_record?
    assert_nil copy.code
    assert_equal 1, copy.revision
    assert_equal source.customer, copy.customer
    assert_equal source.silicone_bp, copy.silicone_bp
    assert_equal source.customer_part_no, copy.customer_part_no
  end

  test "copies line rates from another spec" do
    copy = product_specs(:bf_700).duplicate
    copy.code = "BF-700-250-B"
    copy.save!
    copy.copy_line_rates_from(product_specs(:bf_700))

    assert_equal 190, copy.rate_for(lines(:d1)).kg_per_hour
    assert_equal 175, copy.rate_for(lines(:d2)).kg_per_hour
  end

  test "search covers code, customer and customer references" do
    assert_includes ProductSpec.search("brightform"), product_specs(:bf_700)
    assert_includes ProductSpec.search("2231"), product_specs(:bf_700)
    assert_not_includes ProductSpec.search("2231"), product_specs(:stock)
  end

  test "to_s shows the revision after the first" do
    assert_equal "BF-700-250", product_specs(:bf_700).to_s
    assert_equal "X rev 2", ProductSpec.new(code: "X", revision: 2).to_s
  end
end
