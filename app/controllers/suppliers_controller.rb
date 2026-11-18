class SuppliersController < ApplicationController
  include MasterData
  before_action :set_supplier, only: %i[ edit update ]

  def index
    @suppliers = Supplier.including_inactive(include_inactive?).search(search_query).by_name
  end

  def new
    @supplier = Supplier.new
  end

  def create
    @supplier = Supplier.new(supplier_params)

    if @supplier.save
      redirect_to suppliers_path, notice: "#{@supplier.name} was added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @supplier.update(supplier_params)
      redirect_to suppliers_path, notice: "#{@supplier.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_supplier
      @supplier = Supplier.find(params[:id])
    end

    def supplier_params
      params.expect(supplier: %i[ name country contact_name email phone currency incoterm notes active ])
    end
end
