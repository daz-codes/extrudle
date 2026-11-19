# One feed's share of a spec's recipe, in basis points. Edit a recipe through
# ProductSpec::Recipe, which keeps the shares adding up to 100%.
class SpecIngredient < ApplicationRecord
  belongs_to :product_spec, inverse_of: :ingredients

  enum :feed, MaterialLoad::FEEDS.keys.index_by(&:itself), validate: true

  validates :share_bp, numericality: { only_integer: true, in: 0..10_000 }
  validates :feed, uniqueness: { scope: :product_spec_id }
end
