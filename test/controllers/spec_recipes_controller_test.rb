require "test_helper"

class SpecRecipesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @spec = product_specs(:bf_700)
    sign_in_as users(:office)
  end

  test "saves a recipe from the spec page and goes back to the standard one" do
    get product_spec_path(@spec)
    assert_select "section[aria-labelledby=recipe-heading] input[name='recipe[virgin_coex]'][value='15']"

    patch product_spec_recipe_path(@spec), params: { recipe: { virgin_coex: "10", virgin_mainex: "60", pcw: "20", regrind: "10" } }
    assert_redirected_to product_spec_path(@spec)
    assert_equal "Recipe saved.", flash[:notice]
    assert_equal 6_000, @spec.reload.recipe.shares_bp["virgin_mainex"]

    delete product_spec_recipe_path(@spec)
    assert_not @spec.reload.recipe.custom?
  end

  test "a recipe that doesn't add up isn't saved" do
    patch product_spec_recipe_path(@spec), params: { recipe: { virgin_coex: "10", virgin_mainex: "60" } }
    assert_equal "Recipe not saved: the shares add up to 70%, not 100%.", flash[:alert]
  end

  test "is for the office" do
    sign_in_as users(:floor)
    patch product_spec_recipe_path(@spec), params: { recipe: { virgin_mainex: "100" } }
    assert_redirected_to floor_root_path
    assert_not @spec.reload.recipe.custom?
  end
end
