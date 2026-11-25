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
    assert_equal [ "Spec code is already used by another spec" ], duplicate.errors.full_messages

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
    assert spec.errors.include?(:silicone_pct), "column errors are reported on the form field"
    assert_not spec.errors.include?(:silicone_bp)

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

  test "invalid silicone text is dropped when silicone is switched to none" do
    spec = valid_spec(silicone: "underside", silicone_pct: "1,5")
    assert_not spec.valid?

    spec.silicone = "none"
    assert spec.valid?, spec.errors.full_messages.to_sentence
    assert_nil spec.silicone_pct
  end

  test "input finer than the stored unit is rejected, not rounded" do
    spec = valid_spec(silicone: "underside", silicone_pct: "0.125", max_reel_kg: "0.0004")
    assert_not spec.valid?
    assert_includes spec.errors.full_messages, "Silicone % can have at most 2 decimal places"
    assert_includes spec.errors.full_messages, "Max reel weight can have at most 3 decimal places"
    assert_equal "0.125", spec.silicone_pct

    assert valid_spec(silicone: "underside", silicone_pct: "0.12", max_reel_kg: "0.001").valid?
  end

  test "max reel weight errors appear on the kg field" do
    spec = valid_spec(max_reel_kg: "-5")
    assert_not spec.valid?
    assert spec.errors.include?(:max_reel_kg)
    assert_not spec.errors.include?(:max_reel_g)
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
    assert_equal "1.000", valid_spec(thickness_micron: 1_000).paper_gauge
    assert_equal "1.250", valid_spec(thickness_micron: 1_250).paper_gauge
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

  test "rates on inactive lines are not copied, but stay visible on their spec" do
    source = product_specs(:bf_700)
    lines(:d2).update!(active: false)

    copy = source.duplicate
    copy.code = "BF-700-250-C"
    copy.save!
    copy.copy_line_rates_from(source)

    assert_equal [ lines(:d1) ], copy.line_rates.map(&:line)
    assert_includes source.lines_for_rates, lines(:d2)
    assert_not_includes copy.lines_for_rates, lines(:d2)
  end

  test "saving a copy is all or nothing if the line rates can't be copied" do
    source = product_specs(:bf_700)
    copy = source.duplicate
    copy.code = "BF-700-250-D"
    def copy.copy_line_rates_from(_source) = raise(ActiveRecord::RecordNotUnique)

    assert_no_difference [ "ProductSpec.count", "LineRate.count" ] do
      assert_not copy.save_with_line_rates_from(source)
    end
    assert copy.new_record?
    assert_includes copy.errors.full_messages, "The line rates could not be copied. Please try again."
  end

  test "saving with an invalid spec reports its own errors" do
    spec = valid_spec(width_mm: nil)
    assert_not spec.save_with_line_rates_from(product_specs(:bf_700))
    assert spec.errors.include?(:width_mm)
    assert_not spec.errors.include?(:base)
  end

  test "search covers code, customer and customer references" do
    assert_includes ProductSpec.search("brightform"), product_specs(:bf_700)
    assert_includes ProductSpec.search("2231"), product_specs(:bf_700)
    assert_not_includes ProductSpec.search("2231"), product_specs(:stock)
  end

  test "anti-fog is an optional percentage, copied when duplicated (Q93)" do
    spec = product_specs(:bf_700)
    spec.antifog_pct = "2"
    assert spec.valid?
    assert_equal 200, spec.antifog_bp
    assert_equal 200, spec.duplicate.antifog_bp

    spec.antifog_pct = "0"
    assert_not spec.valid?
    spec.antifog_pct = ""
    assert spec.valid?
    assert_nil spec.antifog_bp
  end

  test "kg per hour on a line: the spec's own rate, else the line's default (Q89)" do
    d1, d2 = lines(:d1), lines(:d2)
    spec = product_specs(:stock)
    assert_nil spec.kg_per_hour_on(d1)
    d1.update!(default_kg_per_hour: 500)
    assert_equal 500, spec.kg_per_hour_on(d1)

    own = product_specs(:bf_700)
    assert_equal own.rate_for(d2).kg_per_hour, own.kg_per_hour_on(d2)
    assert_not d1.tap { _1.default_kg_per_hour = 0 }.valid?
  end

  test "to_s shows the revision after the first" do
    assert_equal "BF-700-250", product_specs(:bf_700).to_s
    assert_equal "X rev 2", ProductSpec.new(code: "X", revision: 2).to_s
  end
end
