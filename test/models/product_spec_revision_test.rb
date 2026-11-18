require "test_helper"

class ProductSpecRevisionTest < ActiveSupport::TestCase
  test "unused specs are updated in place" do
    spec = product_specs(:stock)
    assert_not spec.used?

    revision = ProductSpec::Revision.new(spec, { width_mm: 950 })
    assert revision.save
    assert_not revision.revised?
    assert_equal 950, spec.reload.width_mm
  end

  test "used specs get a new revision and existing orders keep the old one" do
    spec = product_specs(:bf_700)
    assert spec.used?

    revision = ProductSpec::Revision.new(spec, { width_mm: 710, silicone_pct: "0.6" })
    assert_difference "ProductSpec.count" do
      assert revision.save
    end
    assert revision.revised?

    new_spec = revision.spec
    assert_equal [ "BF-700-250", 2 ], [ new_spec.code, new_spec.revision ]
    assert_equal 710, new_spec.width_mm
    assert_equal 60, new_spec.silicone_bp
    assert new_spec.active?
    assert_equal [ 175, 190 ], new_spec.line_rates.map(&:kg_per_hour).sort

    spec.reload
    assert_equal 700, spec.width_mm
    assert_not spec.active?
    assert_equal spec, sales_order_lines(:bf_open_700).reload.product_spec
    assert_equal [ 1, 2 ], spec.revisions.map(&:revision)
  end

  test "toggling active on a used spec doesn't create a revision" do
    spec = product_specs(:bf_700)
    assert_no_difference "ProductSpec.count" do
      assert ProductSpec::Revision.new(spec, { active: false }).save
    end
    assert_not spec.reload.active?
  end

  test "invalid changes don't create anything" do
    spec = product_specs(:bf_700)
    revision = ProductSpec::Revision.new(spec, { width_mm: 0 })
    assert_no_difference "ProductSpec.count" do
      assert_not revision.save
    end
    assert spec.errors.include?(:width_mm)
  end

  test "the code of a used spec can't change" do
    spec = product_specs(:bf_700)
    revision = ProductSpec::Revision.new(spec, { code: "NEW-CODE" })
    assert_not revision.save
    assert spec.errors.include?(:code)
  end

  test "used specs can't be destroyed" do
    assert_not product_specs(:bf_700).destroy
  end
end
