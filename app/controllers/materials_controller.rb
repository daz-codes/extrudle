class MaterialsController < ApplicationController
  include MasterData
  before_action :set_material, only: %i[ edit update ]

  def index
    @materials = Material.including_inactive(include_inactive?).search(search_query)
      .includes(:material_category, :supplier).by_name
    @materials = @materials.where(material_category_id: params[:category]) if params[:category].present?
  end

  def new
    @material = Material.new(material_category_id: params[:category])
  end

  def create
    @material = Material.new(material_params)

    if @material.save
      redirect_to materials_path, notice: "#{@material.name} was added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @material.update(material_params)
      redirect_to materials_path, notice: "#{@material.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_material
      @material = Material.find(params[:id])
    end

    def material_params
      params.expect(material: %i[ name material_category_id supplier_id grade origin source notes active ])
    end
end
