# One line of the log's material section: a bag (lot) going on a feed, from a
# reel number onwards. It feeds that stream until the next bag goes on the same
# feed, or the log ends. Add loads with ProductionRun::LoadMaterial.
class MaterialLoad < ApplicationRecord
  FEEDS = {
    "virgin_coex" => "Virgin Co-Ex",
    "virgin_mainex" => "Virgin Main-Ex",
    "pcw" => "PCW",
    "regrind" => "Regrind"
  }.freeze

  # Working assumption, see PLAN.md §11 Q5 and Q49: the Co-Ex capping polymer
  # comes from one hopper shared by both lines, so its bag can be on both at once.
  SHARED_FEEDS = %w[ virgin_coex ].freeze

  belongs_to :production_run, inverse_of: :material_loads
  belongs_to :lot
  belongs_to :user, optional: true

  enum :feed, FEEDS.keys.index_by(&:itself), validate: true

  normalizes :initials, with: ->(text) { text.strip.upcase.presence }
  normalizes :note, with: ->(text) { text.strip.presence }

  validates :from_reel_no, numericality: { only_integer: true, greater_than: 0 }
  validates :loaded_at, presence: true
  validate :run_is_running, on: :create

  before_validation { self.loaded_at ||= Time.current }

  def self.feed_label(feed) = FEEDS.fetch(feed.to_s)

  # The feed a bag usually goes on, from its material: in-house regrind,
  # recycled flake on PCW, capping polymer on Co-Ex, other virgin on Main-Ex.
  def self.feed_for(material)
    return if material.nil?
    return "regrind" if material.internal?
    return "pcw" if material.recycled?

    material.material_category.name.match?(/cap|co-?ex/i) ? "virgin_coex" : "virgin_mainex"
  end

  def feed_label = self.class.feed_label(feed)

  def shared_feed? = SHARED_FEEDS.include?(feed)

  private
    def run_is_running
      return if production_run.nil? || production_run.running?

      errors.add(:base, "Despatch #{production_run.despatch_number} is finished, so its materials can't change")
    end
end
