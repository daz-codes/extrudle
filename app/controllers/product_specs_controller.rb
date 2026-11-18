class ProductSpecsController < ApplicationController
  include MasterData
  before_action :set_product_spec, only: %i[ show edit update summary ]

  def index
    @product_specs = ProductSpec.including_inactive(include_inactive?).search(search_query)
      .includes(:customer, line_rates: :line).by_code
    @product_specs = @product_specs.where(customer_id: params[:customer]) if params[:customer].present?
  end

  def show
    @lines = @product_spec.lines_for_rates
  end

  # ?copy_from=ID prefills the form from an existing spec ("Duplicate as new").
  def new
    @source = ProductSpec.find_by(id: params[:copy_from])
    @product_spec = @source ? @source.duplicate : ProductSpec.new(customer_id: params[:customer])
  end

  def create
    @product_spec = ProductSpec.new(product_spec_params)
    @source = ProductSpec.find_by(id: params[:copy_from])

    if @product_spec.save_with_line_rates_from(@source)
      redirect_to @product_spec, notice: "Spec #{@product_spec} was added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    revision = ProductSpec::Revision.new(@product_spec, product_spec_params)

    if revision.save
      notice = if revision.revised?
        "Spec #{@product_spec.code} is used on orders, so your changes were saved as revision #{revision.spec.revision}. " \
          "Existing orders keep revision #{@product_spec.revision}."
      else
        "Spec #{revision.spec} was updated."
      end
      redirect_to revision.spec, notice: notice
    else
      render :edit, status: :unprocessable_content
    end
  end

  # Read-only spec details for the order line form (loaded into a Turbo frame).
  def summary
    render partial: "product_specs/summary", locals: { spec: @product_spec }
  end

  private
    def set_product_spec
      @product_spec = ProductSpec.find(params[:id])
    end

    def product_spec_params
      params.expect(product_spec: %i[
        code customer_id width_mm thickness_micron material_type pe silicone silicone_pct antiblock
        core_inches core_orientation reel_limit max_diameter_mm max_reel_kg pallet_type reels_per_pallet
        label_inside_core packaging_notes customer_part_no customer_tool_no customer_product_code
        customer_description active
      ])
    end
end
