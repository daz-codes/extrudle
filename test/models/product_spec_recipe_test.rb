require "test_helper"

class ProductSpecRecipeTest < ActiveSupport::TestCase
  setup { @spec = product_specs(:bf_700) }

  test "a spec without its own recipe uses the standard one" do
    recipe = @spec.recipe
    assert_not recipe.custom?
    assert_equal ProductSpec::Recipe::STANDARD_BP, recipe.shares_bp
    assert_equal 10_000, recipe.shares_bp.values.sum
    assert_equal "15", recipe.percent("virgin_coex")
  end

  test "saves a recipe that adds up to 100%, with blanks as 0" do
    assert @spec.recipe.update("virgin_coex" => "12.5", "virgin_mainex" => "57.5", "pcw" => "30", "regrind" => "")
    recipe = @spec.reload.recipe
    assert recipe.custom?
    assert_equal({ "virgin_coex" => 1_250, "virgin_mainex" => 5_750, "pcw" => 3_000, "regrind" => 0 }, recipe.shares_bp)
  end

  test "rejects shares that don't add up to 100% and keeps what was typed" do
    recipe = @spec.recipe
    assert_not recipe.update("virgin_coex" => "15", "virgin_mainex" => "50", "pcw" => "25", "regrind" => "5")
    assert_equal [ "The shares add up to 95%, not 100%" ], recipe.errors.full_messages
    assert_equal "5", recipe.percent("regrind")
    assert_not @spec.reload.recipe.custom?
  end

  test "rejects text, too many decimals and negative shares" do
    recipe = @spec.recipe
    assert_not recipe.update("virgin_coex" => "lots", "virgin_mainex" => "50.125", "pcw" => "25", "regrind" => "10")
    assert_includes recipe.errors.full_messages, "Virgin Co-Ex is not a number"
    assert_includes recipe.errors.full_messages, "Virgin Main-Ex can have at most 2 decimal places"

    recipe = @spec.recipe
    assert_not recipe.update("virgin_coex" => "-10", "virgin_mainex" => "110", "pcw" => "", "regrind" => "")
    assert_includes recipe.errors.full_messages, "Virgin Co-Ex must be between 0% and 100%"
  end

  test "reset goes back to the standard recipe" do
    @spec.recipe.update("virgin_coex" => "10", "virgin_mainex" => "90")
    @spec.recipe.reset
    assert_not @spec.reload.recipe.custom?
  end

  test "a new revision and a duplicate keep the recipe" do
    @spec.recipe.update("virgin_coex" => "10", "virgin_mainex" => "60", "pcw" => "30")
    revision = ProductSpec::Revision.new(@spec, { "packaging_notes" => "New pallets" })
    assert revision.save
    assert revision.revised?, "bf_700 is on an order, so it should be revised"
    assert_equal @spec.recipe.shares_bp, revision.spec.recipe.shares_bp

    copy = @spec.duplicate
    copy.code = "BF-700-COPY"
    assert copy.save_with_line_rates_from(@spec)
    assert_equal @spec.recipe.shares_bp, copy.recipe.shares_bp
  end
end
