# Moves whole lots to another location. Working assumption, see PLAN.md §11 Q28:
# a bag moves as a whole, so a transfer never splits a lot.
class Stock::Transfer
  class Error < StandardError; end

  def self.call(lots, to:, user: nil, note: nil)
    new(lots, to:, user:, note:).call
  end

  def initialize(lots, to:, user: nil, note: nil)
    @lots, @to, @user, @note = Array(lots), to.to_s, user, note.presence
  end

  # Returns the lots that moved (lots already there are skipped).
  def call
    raise Error, "Choose where to move it" unless Lot::LOCATIONS.key?(@to)

    Lot.transaction do
      @lots.reject { _1.location == @to }.each do |lot|
        lot.movements.create!(kind: "transfer", quantity_g: 0, from_location: lot.location, to_location: @to, user: @user, note: @note)
        lot.update!(location: @to)
      end
    end
  end
end
