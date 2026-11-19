# The recipe card on a spec page: each feed's share, or back to the standard recipe.
class SpecRecipesController < ApplicationController
  include MasterData
  before_action :set_product_spec

  def update
    recipe = @product_spec.recipe
    if recipe.update(params.fetch(:recipe, {}).permit(*ProductSpec::Recipe::FEEDS).to_h)
      redirect_to @product_spec, notice: "Recipe saved."
    else
      redirect_to @product_spec, alert: "Recipe not saved: #{recipe.errors.full_messages.to_sentence.downcase_first}."
    end
  end

  def destroy
    @product_spec.recipe.reset
    redirect_to @product_spec, notice: "This spec now uses the standard recipe.", status: :see_other
  end

  private
    def set_product_spec
      @product_spec = ProductSpec.find(params[:product_spec_id])
    end
end
