# A spec's recipe: what share of the film comes from each feed. Used to work
# out how much of each stream a production run used (see PLAN.md §4).
#
# Specs without their own recipe use the standard one. Working assumption, see
# PLAN.md §11 Q6: we don't know the real shares yet.
#
# Like line rates, the recipe is production data, so it can change on a used
# spec without a new revision. Finished runs keep what was allocated then.
class ProductSpec::Recipe
  include ActiveModel::Model

  FEEDS = MaterialLoad::FEEDS.keys.freeze
  STANDARD_BP = { "virgin_coex" => 1_500, "virgin_mainex" => 5_000, "pcw" => 2_500, "regrind" => 1_000 }.freeze

  attr_reader :spec

  def initialize(spec)
    @spec = spec
    @input = {}
  end

  def self.shares_for(spec) = new(spec).shares_bp

  def custom? = spec.ingredients.any?

  # { "virgin_coex" => 1500, … } for every feed, adding up to 10000.
  def shares_bp
    return STANDARD_BP unless custom?

    stored = spec.ingredients.to_h { [ _1.feed, _1.share_bp ] }
    FEEDS.index_with { stored.fetch(_1, 0) }
  end

  # The percentage shown in the form: what was typed, or the saved share.
  def percent(feed)
    @input.fetch(feed.to_s) { DecimalInput.from_scaled_integer(shares_bp.fetch(feed.to_s), 100) }
  end

  # Takes { "virgin_coex" => "15", … } in percent. Blank counts as 0.
  def update(percentages)
    @input = FEEDS.index_with { percentages.fetch(_1, "").to_s.strip }
    shares = parse
    return false unless shares

    ProductSpec.transaction do
      spec.ingredients.destroy_all
      shares.each { |feed, share_bp| spec.ingredients.create!(feed:, share_bp:) }
    end
    spec.ingredients.reset
    @input = {}
    true
  end

  # Back to the standard recipe.
  def reset
    spec.ingredients.destroy_all
    spec.ingredients.reset
  end

  private
    def parse
      shares = @input.to_h do |feed, text|
        [ feed, text.empty? ? 0 : DecimalInput.to_scaled_integer(text, 100, exact: true) ]
      rescue DecimalInput::TooPrecise
        errors.add(:base, "#{MaterialLoad.feed_label(feed)} can have at most 2 decimal places")
        [ feed, nil ]
      rescue DecimalInput::Invalid
        errors.add(:base, "#{MaterialLoad.feed_label(feed)} is not a number")
        [ feed, nil ]
      end
      return if errors.any?

      shares.each { |feed, bp| errors.add(:base, "#{MaterialLoad.feed_label(feed)} must be between 0% and 100%") unless bp.between?(0, 10_000) }
      total = shares.values.sum
      errors.add(:base, "The shares add up to #{DecimalInput.from_scaled_integer(total, 100)}%, not 100%") if errors.empty? && total != 10_000
      shares if errors.empty?
    end
end
