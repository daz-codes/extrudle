class SalesOrderLine < ApplicationRecord
  include ScaledAttributes
  include EnteredQuantity

  belongs_to :sales_order, inverse_of: :lines
  belongs_to :product_spec
  has_many :schedule_blocks, dependent: :restrict_with_error
  has_many :production_runs, dependent: :restrict_with_error

  # The price is agreed in the customer's currency when the line is added, and kept with it.
  scaled_attribute :price_per_tonne, column: :price_per_tonne_cents, scale: 100, pad: true

  validates :currency, inclusion: { in: Money::CURRENCIES.keys }
  validates :price_per_tonne_cents, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validate :spec_suits_the_order, if: -> { new_record? || will_save_change_to_product_spec_id? }
  validate :order_is_editable

  before_validation :take_currency_from_customer, on: :create
  validate :spec_fixed_while_planned, on: :update
  after_save -> { sales_order.refresh_schedule_status! }, if: :saved_change_to_quantity_g?
  after_destroy -> { sales_order.refresh_schedule_status! }

  normalizes :customer_batch_no, with: ->(no) { no.strip.presence }

  delegate :customer, to: :sales_order

  # Weight put on the planner in job blocks, across all lines.
  def planned_g
    schedule_blocks.loaded? ? schedule_blocks.select(&:job?).sum(&:planned_g) : schedule_blocks.jobs.sum(:planned_g)
  end

  def unplanned_g
    [ quantity_g.to_i - planned_g, 0 ].max
  end

  def fully_planned?
    planned_g >= quantity_g.to_i
  end

  private
    def take_currency_from_customer
      self.currency = customer.currency if sales_order&.customer
    end

    # A planned job's duration and changeovers depend on its spec.
    def spec_fixed_while_planned
      return unless will_save_change_to_product_spec_id? && schedule_blocks.exists?

      errors.add(:product_spec, "can't change while this line is on the planner. Take it off the plan first.")
    end

    def spec_suits_the_order
      return unless product_spec && sales_order

      errors.add(:product_spec, "is inactive") unless product_spec.active?
      if product_spec.customer_id && product_spec.customer_id != sales_order.customer_id
        errors.add(:product_spec, "belongs to another customer")
      end
    end

    def order_is_editable
      errors.add(:base, "Order #{sales_order.number} is #{sales_order.status.humanize.downcase} and can't be changed") if sales_order && !sales_order.editable?
    end
end
