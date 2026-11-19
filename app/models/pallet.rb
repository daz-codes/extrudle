# A pallet of finished reels: the reels of one production log with the same
# pallet number ("731/2"). Not stored: it's worked out from the reels, and a
# DeliveryNotePallet records it going out. Working assumption, see PLAN.md §11 Q42.
class Pallet
  attr_reader :run, :pallet_no, :reels

  def self.for_run(run)
    run.reels.select(&:pallet_no).group_by(&:pallet_no).sort.map { |pallet_no, reels| new(run, pallet_no, reels) }
  end

  def initialize(run, pallet_no, reels)
    @run = run
    @pallet_no = pallet_no
    @reels = reels.sort_by(&:reel_no)
  end

  def key = "#{run.id}-#{pallet_no}"
  def label = "#{run.despatch_number}/#{pallet_no}"

  def weight_g = reels.sum(&:weight_g)
  def reel_count = reels.size
  def reel_numbers = reels.map(&:reel_no)

  def order_line = run.sales_order_line
  def product_spec = run.product_spec

  # Ready to go: the log is finished, a later pallet has been started, or it
  # holds the spec's reels per pallet. Working assumption, see PLAN.md §11 Q64.
  def complete?
    return true if run.finished?
    return true if run.reels.any? { _1.pallet_no && _1.pallet_no > pallet_no }

    per_pallet = product_spec.reels_per_pallet
    per_pallet.present? && reel_count >= per_pallet
  end

  def ==(other) = other.is_a?(Pallet) && other.run.id == run.id && other.pallet_no == pallet_no
  alias eql? ==
  def hash = [ run.id, pallet_no ].hash
end
