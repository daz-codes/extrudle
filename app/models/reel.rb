# A finished reel: one line of page 2 of the production log. Numbered 1, 2, 3…
# within its run, timed when it's entered. The run's total is the sum of its
# reels and is never stored.
class Reel < ApplicationRecord
  include ScaledAttributes

  belongs_to :production_run, inverse_of: :reels
  belongs_to :user, optional: true

  scaled_attribute :weight_kg, column: :weight_g, scale: Weight::GRAMS_PER_KG

  normalizes :initials, with: ->(text) { text.strip.upcase.presence }

  validates :reel_no, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :production_run_id }
  validates :weight_g, presence: true, numericality: { only_integer: true, greater_than: 0 }
  validates :length_m, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :pallet_no, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
  validates :produced_at, presence: true
  validate :run_is_running

  before_validation :number_and_time, on: :create

  # Over the spec's maximum reel weight. A warning, not an error.
  def over_max_weight?
    max = production_run&.product_spec&.max_reel_g
    max.present? && weight_g.to_i > max
  end

  private
    def number_and_time
      self.reel_no ||= production_run&.next_reel_no
      self.produced_at ||= Time.current
    end

    def run_is_running
      return if production_run.nil? || production_run.running?

      errors.add(:base, "Despatch #{production_run.despatch_number} is finished, so its reels can't change")
    end
end
