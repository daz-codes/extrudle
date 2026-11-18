class MaterialCategoriesController < ApplicationController
  include MasterData
  before_action :set_material_category, only: %i[ edit update ]

  def index
    @material_categories = MaterialCategory.ordered.includes(:materials)
  end

  def new
    @material_category = MaterialCategory.new(position: (MaterialCategory.maximum(:position) || 0) + 1)
  end

  def create
    @material_category = MaterialCategory.new(material_category_params)

    if @material_category.save
      redirect_to material_categories_path, notice: "#{@material_category.name} was added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @material_category.update(material_category_params)
      redirect_to material_categories_path, notice: "#{@material_category.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_material_category
      @material_category = MaterialCategory.find(params[:id])
    end

    def material_category_params
      params.expect(material_category: %i[ name description position ])
    end
end
