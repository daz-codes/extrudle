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

  test "a superseded revision can't be revised, but can still be deactivated" do
    rev1 = product_specs(:bf_700)
    assert ProductSpec::Revision.new(rev1, { width_mm: 710 }).save
    rev1.reload
    assert_not rev1.latest_revision?

    stale = ProductSpec::Revision.new(rev1, { width_mm: 720 })
    assert_no_difference "ProductSpec.count" do
      assert_not stale.save
    end
    assert_match "replaced by revision 2", rev1.errors.full_messages.to_sentence
    assert_equal 720, rev1.width_mm, "the user's edit is kept for the form"
    assert_equal 1, ProductSpec.active.where(code: "BF-700-250").count

    assert ProductSpec::Revision.new(rev1.reload, { active: true }).save, "toggling Active stays allowed"
  end

  test "unticking Active in the same edit retires the new revision too" do
    spec = product_specs(:bf_700)
    revision = ProductSpec::Revision.new(spec, { width_mm: 710, active: false })
    assert revision.save
    assert revision.revised?
    assert_not revision.spec.active?
    assert_not spec.reload.active?
    assert_equal 0, ProductSpec.active.where(code: "BF-700-250").count
  end

  test "creating a revision leaves the user's edits on the original in memory" do
    spec = product_specs(:bf_700)
    assert ProductSpec::Revision.new(spec, { width_mm: 710 }).save
    assert_equal 710, spec.width_mm
    assert_equal 700, spec.reload.width_mm
  end

  test "used specs can't be destroyed" do
    assert_not product_specs(:bf_700).destroy
  end
end
