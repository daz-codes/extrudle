class LineRatesController < ApplicationController
  include MasterData
  before_action :set_product_spec

  def create
    @line_rate = @product_spec.line_rates.find_or_initialize_by(line_id: params.dig(:line_rate, :line_id))
    @line_rate.kg_per_hour = params.dig(:line_rate, :kg_per_hour)
    save_and_redirect
  end

  def update
    @line_rate = @product_spec.line_rates.find(params[:id])
    @line_rate.kg_per_hour = params.dig(:line_rate, :kg_per_hour)
    save_and_redirect
  end

  def destroy
    line_rate = @product_spec.line_rates.find(params[:id])
    line_rate.destroy!
    redirect_to @product_spec, notice: "Rate for line #{line_rate.line.name} was removed.", status: :see_other
  end

  private
    def set_product_spec
      @product_spec = ProductSpec.find(params[:product_spec_id])
    end

    def save_and_redirect
      if @line_rate.save
        redirect_to @product_spec, notice: "Rate for line #{@line_rate.line.name} saved."
      else
        redirect_to @product_spec, alert: "Line #{@line_rate.line&.name}: #{@line_rate.errors.full_messages.to_sentence}"
      end
    end
end
