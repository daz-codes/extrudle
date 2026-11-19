require "test_helper"

class AllocationTest < ActiveSupport::TestCase
  test "parts always add up to the total" do
    assert_equal [ 4, 3, 3 ], Allocation.largest_remainder(10, [ 1, 1, 1 ])
    assert_equal [ 7_333_334, 7_333_333, 7_333_333 ], Allocation.evenly(22_000_000, 3)
    [ [ 1_000_003, [ 3, 5, 7 ] ], [ 999, [ 1, 0, 2 ] ], [ 0, [ 4, 4 ] ] ].each do |total, weights|
      assert_equal total, Allocation.largest_remainder(total, weights).sum
    end
  end

  test "the leftover goes to the largest remainders, ties to the earlier part" do
    # 100 × [1, 2, 3] / 6 = 16.67, 33.33, 50 → 17, 33, 50
    assert_equal [ 17, 33, 50 ], Allocation.largest_remainder(100, [ 1, 2, 3 ])
    assert_equal [ 1, 1, 0 ], Allocation.evenly(2, 3)
    assert_equal [ 0, 5, 0 ], Allocation.largest_remainder(5, [ 0, 1, 0 ])
  end

  test "rejects bad input" do
    assert_raises(ArgumentError) { Allocation.largest_remainder(10, [ 0, 0 ]) }
    assert_raises(ArgumentError) { Allocation.largest_remainder(-1, [ 1 ]) }
    assert_raises(ArgumentError) { Allocation.largest_remainder(10, [ 1.5 ]) }
  end
end
