require "test_helper"

class PlannerHelperTest < ActionView::TestCase
  test "hours as the paper plan writes them" do
    assert_equal [ "10", "10½", "½", "0", "26" ], [ 600, 630, 30, 0, 1_560 ].map { print_hours(_1) }
  end
end
