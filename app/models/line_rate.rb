class LineRate < ApplicationRecord
  belongs_to :line
  belongs_to :product_spec

  validates :kg_per_hour, numericality: { only_integer: true, greater_than: 0 }
  validates :line_id, uniqueness: { scope: :product_spec_id }
end
