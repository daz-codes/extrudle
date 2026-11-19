# Corrects a lot's weight after a recount or reweigh: the counted weight is
# entered and the difference is posted as an adjustment movement with a reason.
class Stock::Adjustment
  include ActiveModel::Model
  include ActiveModel::Attributes
  include ActiveModel::Validations::Callbacks
  include ScaledAttributes

  attribute :counted_g, :integer
  attribute :reason, :string

  scaled_attribute :counted_kg, column: :counted_g, scale: Weight::GRAMS_PER_KG

  attr_reader :lot, :movement
  attr_accessor :user

  validates :counted_g, presence: true, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :reason, presence: true
  validate :weight_changes

  def initialize(lot:, **attributes)
    @lot = lot
    super(**attributes)
  end

  # ScaledAttributes reads and writes the integer column with [].
  def [](name) = public_send(name)
  def []=(name, value)
    public_send("#{name}=", value)
  end

  def difference_g = counted_g.to_i - lot.quantity_g

  def save!
    save || raise(ActiveRecord::RecordInvalid.new(self))
  end

  def save
    return false unless valid?

    @movement = lot.movements.create!(kind: "adjustment", quantity_g: difference_g, user:, note: reason)
    true
  end

  private
    def weight_changes
      errors.add(:counted_kg, "is the same as the current weight") if counted_g && difference_g.zero?
    end
end
