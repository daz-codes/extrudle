# Splits an integer total (e.g. grams) in proportion to integer weights so the
# parts add up exactly. The leftover from rounding down goes one unit at a time
# to the parts with the largest remainders (ties go to the earlier part).
# See CLAUDE.md: allocations use the largest-remainder method.
#
#   Allocation.largest_remainder(10, [ 1, 1, 1 ]) #=> [ 4, 3, 3 ]
#   Allocation.evenly(22_000_000, 3)              #=> [ 7_333_334, 7_333_333, 7_333_333 ]
module Allocation
  module_function

  def largest_remainder(total, weights)
    raise ArgumentError, "total must be a non-negative integer" unless total.is_a?(Integer) && total >= 0
    raise ArgumentError, "weights must be non-negative integers" unless weights.all? { _1.is_a?(Integer) && _1 >= 0 }

    sum = weights.sum
    raise ArgumentError, "weights must not all be zero" if sum.zero?

    shares = weights.map { |weight| (total * weight).divmod(sum) }
    leftover = total - shares.sum(&:first)
    winners = shares.each_with_index.sort_by { |(_, remainder), index| [ -remainder, index ] }.first(leftover).map(&:last)

    shares.each_with_index.map { |(share, _), index| winners.include?(index) ? share + 1 : share }
  end

  def evenly(total, parts)
    largest_remainder(total, Array.new(parts, 1))
  end
end
