# Document numbers like SO-00001 and PO-00001, handed out in order.
#
#   include SequentialNumber
#   numbered_with "PO"   # PO-00001, PO-00002 … PO-99999, PO-100000
#
# Create with `save_with_number`, which takes the next number if another user
# grabbed the same one at the same moment.
module SequentialNumber
  extend ActiveSupport::Concern

  included do
    class_attribute :number_prefix, instance_writer: false
    validates :number, presence: true, uniqueness: true
    before_validation :assign_number, on: :create
  end

  class_methods do
    def numbered_with(prefix)
      self.number_prefix = prefix
    end

    # Compares the numeric part, so PO-100000 comes after PO-99999.
    def next_number
      start = number_prefix.length + 2
      last = where("number LIKE ?", "#{number_prefix}-%").pick(Arel.sql(sanitize_sql_array([ "MAX(CAST(SUBSTR(number, ?) AS INTEGER))", start ])))
      format("%s-%05d", number_prefix, last.to_i + 1)
    end
  end

  # Like save, but if another user took the same number at the same moment, takes the next one.
  def save_with_number(attempts: 3)
    save
  rescue ActiveRecord::RecordNotUnique
    raise if (attempts -= 1).zero?

    self.number = nil
    retry
  end

  private
    def assign_number
      self.number ||= self.class.next_number
    end
end
