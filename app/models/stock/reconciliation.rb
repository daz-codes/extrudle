# A bag marked empty is reconciled (PLAN.md §4): whatever its book weight still
# says after every run that used it has been allocated is posted as an
# adjustment, so the lot ends at zero. That adjustment is the bag's variance:
# negative when the line used more than the recipe says, positive when less.
#
# A bag can be marked empty while a log that used it is still running. It is
# reconciled when the last of those logs finishes (ProductionRun#finish!).
class Stock::Reconciliation
  NOTE = "Bag empty: variance against what production used"

  def self.mark_empty(lot, user: nil, at: Time.current)
    lot.update!(emptied_at: at) unless lot.emptied_at
    call(lot, user:)
  end

  # Not empty after all: only until it has been reconciled.
  def self.unmark_empty(lot)
    raise ArgumentError, "#{lot.code} has already been reconciled" if lot.reconciled_at

    lot.update!(emptied_at: nil)
  end

  # Logs still running that used the lot.
  def self.waiting_on(lot)
    ProductionRun.running.where(id: MaterialLoad.where(lot_id: lot.id).select(:production_run_id))
  end

  # Returns the adjustment movement (or nil when there was nothing to post).
  def self.call(lot, user: nil)
    return unless lot.emptied_at && lot.reconciled_at.nil?
    return if waiting_on(lot).exists?

    Lot.transaction do
      lot.lock!
      remaining = lot.movements.sum(:quantity_g)
      movement = lot.movements.create!(kind: "adjustment", quantity_g: -remaining, user:, note: NOTE) unless remaining.zero?
      lot.update!(reconciled_at: Time.current)
      movement
    end
  end
end
