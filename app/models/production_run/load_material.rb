# Records a bag going on a feed: the log's "JADE bag 939, reels 1–5". The bag
# is found by its lot code, typed or scanned (a scanner types the code and
# presses Enter). The feed is picked from the bag's material if not chosen.
#
# The bag that was on the feed before is marked empty, unless the operator
# says it isn't (a part-used bag taken off goes back to stock as it is).
# Working assumption, see PLAN.md §11 Q48.
class ProductionRun::LoadMaterial
  include ActiveModel::Model
  include ActiveModel::Attributes

  LOADABLE_LOCATIONS = %w[ on_site storage ].freeze

  attribute :lot_code, :string
  attribute :feed, :string
  attribute :from_reel_no, :integer
  attribute :initials, :string
  attribute :note, :string
  attribute :previous_empty, :boolean, default: true

  attr_reader :run, :load
  attr_accessor :user

  validates :lot_code, presence: true
  validates :from_reel_no, numericality: { only_integer: true, greater_than: 0 }
  validate :run_is_running
  validate :lot_can_go_on

  def initialize(run:, **attributes)
    @run = run
    super(**attributes)
    self.from_reel_no ||= run.next_reel_no
    self.initials ||= run.material_loads.last&.initials || run.reels.last&.initials
  end

  def lot_code=(value)
    super(value.to_s.strip.upcase.presence)
    @lot = nil
  end

  def lot
    @lot ||= lot_code && Lot.includes(material: :material_category).find_by(code: lot_code)
  end

  def chosen_feed
    feed.presence || MaterialLoad.feed_for(lot&.material)
  end

  # The bag on the chosen feed now, if any.
  def previous_load
    chosen_feed && run.current_loads[chosen_feed]
  end

  def save
    return false unless valid?

    MaterialLoad.transaction do
      previous = previous_load
      empties_previous = previous.present? && previous.lot_id != lot.id && previous_empty && !previous.lot.emptied?
      @load = run.material_loads.create!(lot:, feed: chosen_feed, from_reel_no:, initials:, note:, user:,
                                         marked_previous_empty: empties_previous)
      Stock::Transfer.call(lot, to: "on_site", user:, note: "Loaded on line #{run.line.name}") if lot.storage?
      Stock::Reconciliation.mark_empty(previous.lot, user:) if empties_previous
    end
    run.material_loads.reset
    true
  rescue ActiveRecord::RecordInvalid => e
    e.record.errors.each { |error| errors.add(:base, error.full_message) }
    false
  end

  private
    def run_is_running
      errors.add(:base, "Despatch #{run.despatch_number} is finished, so its materials can't change") unless run.running?
    end

    def lot_can_go_on
      return if lot_code.blank?
      return errors.add(:lot_code, "#{lot_code} isn't a lot code we know") unless lot

      if lot.emptied_at
        errors.add(:lot_code, "#{lot.code} was marked empty")
      elsif !LOADABLE_LOCATIONS.include?(lot.location)
        errors.add(:lot_code, "#{lot.code} is #{lot.location_label.downcase}, not on site")
      elsif !MaterialLoad::FEEDS.key?(chosen_feed)
        errors.add(:feed, "can't be blank")
      elsif run.current_loads[chosen_feed]&.lot_id == lot.id
        errors.add(:lot_code, "#{lot.code} is already on #{MaterialLoad.feed_label(chosen_feed)}")
      elsif (elsewhere = MaterialLoad.feeding_elsewhere(lot, run:, feed: chosen_feed))
        errors.add(:lot_code, "#{lot.code} is on #{elsewhere}. Mark it empty or load another bag there first")
      end
    end
end
