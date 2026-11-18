class MasterDataController < ApplicationController
  include MasterData

  def show
    @counts = {
      customers: Customer.active.count,
      suppliers: Supplier.active.count,
      material_categories: MaterialCategory.count,
      materials: Material.active.count,
      lines: Line.active.count,
      product_specs: ProductSpec.active.count
    }
  end
end
