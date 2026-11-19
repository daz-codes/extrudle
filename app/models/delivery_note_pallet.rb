# A pallet going out on a delivery note. A pallet goes out once (unique index).
class DeliveryNotePallet < ApplicationRecord
  belongs_to :delivery_note, inverse_of: :note_pallets
  belongs_to :production_run

  validates :pallet_no, numericality: { only_integer: true, greater_than: 0 }
  validates :pallet_no, uniqueness: { scope: :production_run_id, message: "is already on another delivery note" }

  def pallet = Pallet.new(production_run, pallet_no, production_run.reels.select { _1.pallet_no == pallet_no })
end
