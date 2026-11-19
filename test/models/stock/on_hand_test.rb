require "test_helper"

class Stock::OnHandTest < ActiveSupport::TestCase
  test "totals per material and location, with what's on order" do
    report = Stock::OnHand.new
    rows = report.groups.flat_map(&:rows).index_by(&:material)

    jade = rows.fetch(materials(:jade))
    assert_equal({ "on_site" => 1_000_000 }, jade.by_location)
    assert_equal 1, jade.lots
    assert_equal 1_100_000, jade.on_order_g # albion_sent; drafts and received POs don't count

    assert_equal({ "storage" => 500_000 }, rows.fetch(materials(:regrind)).by_location)
    assert_equal 1_500_000, report.total_g
  end

  test "on order drops as goods come in" do
    Stock::Receipt.new(purchase_order_line: purchase_order_lines(:albion_jade), quantity: "400").save!
    jade = Stock::OnHand.new.groups.flat_map(&:rows).find { _1.material == materials(:jade) }
    assert_equal 700_000, jade.on_order_g
    assert_equal 1_400_000, jade.total_g
  end
end
