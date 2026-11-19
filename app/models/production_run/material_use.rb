# Works out how much of each bag a run used (PLAN.md §4). Nobody weighs bags
# going into the line, so:
#
# 1. The run's output (the sum of its reels) is split across the feeds by the
#    spec's recipe.
# 2. Each feed's share is split across the bags loaded on that feed, in
#    proportion to the weight of the reels each bag fed.
#
# All in integer grams with the largest-remainder method, so the bags add up
# exactly to the feed and the feeds to the output.
#
# A bag feeds its stream from its load's reel number until the next bag goes on
# the same feed. The first bag on a feed also covers any reels before it (it was
# feeding the line before anyone wrote it down). Feeds in the recipe with no
# bag recorded are left out, and their share goes to the feeds that had bags.
#
# Working assumption, see PLAN.md §11 Q46: material used = reels made. Edge
# trim and scrap show up later as the variance when a bag is marked empty.
class ProductionRun::MaterialUse
  Share = Data.define(:load, :quantity_g) do
    delegate :lot, :feed, :feed_label, to: :load
  end

  attr_reader :run

  def initialize(run)
    @run = run
  end

  def recipe = ProductSpec::Recipe.shares_for(run.product_spec)

  def loads_by_feed
    @loads_by_feed ||= run.material_loads.to_a.group_by(&:feed)
  end

  # Feeds with a share in the recipe but no bag recorded on this log.
  def missing_feeds
    recipe.select { |feed, share| share.positive? && !loads_by_feed.key?(feed) }.keys
  end

  # { feed => grams } over the feeds that had bags.
  def feed_totals
    @feed_totals ||= begin
      shares = recipe.select { |feed, share| share.positive? && loads_by_feed.key?(feed) }
      if shares.empty? || run.total_g.zero?
        {}
      else
        shares.keys.zip(Allocation.largest_remainder(run.total_g, shares.values)).to_h
      end
    end
  end

  # One Share per load, in feed order.
  def lines
    @lines ||= feed_totals.flat_map do |feed, total_g|
      loads = loads_by_feed.fetch(feed)
      weights = loads.map { |load| reels_fed_by(load, loads).sum(&:weight_g) }
      loads.zip(Allocation.largest_remainder(total_g, weights)).map { |load, grams| Share.new(load:, quantity_g: grams) }
    end
  end

  # { lot => grams }: a bag that went on twice is one issue.
  def by_lot
    lines.group_by(&:lot).transform_values { _1.sum(&:quantity_g) }.select { |_, grams| grams.positive? }
  end

  def total_g = lines.sum(&:quantity_g)

  # Posts one issue_to_production movement per bag. Call once, when the run finishes.
  def post!(user: nil)
    by_lot.each do |lot, grams|
      lot.movements.create!(kind: "issue_to_production", quantity_g: -grams, production_run: run, user:,
                            note: "Despatch #{run.despatch_number} on line #{run.line.name}")
    end
  end

  private
    def reels_fed_by(load, loads)
      index = loads.index(load)
      from = index.zero? ? 1 : load.from_reel_no
      to = loads[index + 1]&.from_reel_no&.pred
      run.reels.select { |reel| reel.reel_no >= from && (to.nil? || reel.reel_no <= to) }
    end
end
