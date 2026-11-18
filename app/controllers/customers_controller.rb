class CustomersController < ApplicationController
  include MasterData
  before_action :set_customer, only: %i[ show edit update ]

  def index
    @customers = Customer.including_inactive(include_inactive?).search(search_query).by_name
  end

  def show
    @product_specs = @customer.product_specs.by_code
  end

  def new
    @customer = Customer.new
  end

  def create
    @customer = Customer.new(customer_params)

    if @customer.save
      redirect_to @customer, notice: "#{@customer.name} was added."
    else
      render :new, status: :unprocessable_content
    end
  end

  def edit
  end

  def update
    if @customer.update(customer_params)
      redirect_to @customer, notice: "#{@customer.name} was updated."
    else
      render :edit, status: :unprocessable_content
    end
  end

  private
    def set_customer
      @customer = Customer.find(params[:id])
    end

    def customer_params
      params.expect(customer: %i[ name contact_name email phone address currency notes active ])
    end
end
