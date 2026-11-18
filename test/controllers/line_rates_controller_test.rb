require "test_helper"

class LineRatesControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in_as users(:office)
    @spec = product_specs(:stock)
  end

  test "create a rate" do
    assert_difference "LineRate.count" do
      post product_spec_line_rates_path(@spec), params: { line_rate: { line_id: lines(:d1).id, kg_per_hour: "230" } }
    end
    assert_redirected_to product_spec_path(@spec)
    assert_equal 230, @spec.rate_for(lines(:d1)).kg_per_hour
  end

  test "a missing, unknown or inactive line is rejected" do
    lines(:d2).update!(active: false)
    [ "", "0", lines(:d2).id ].each do |line_id|
      assert_no_difference "LineRate.count" do
        post product_spec_line_rates_path(@spec), params: { line_rate: { line_id:, kg_per_hour: "230" } }
      end
      assert_redirected_to product_spec_path(@spec)
      assert_equal "Choose an active line.", flash[:alert]
    end
  end

  test "creating twice for a line updates the existing rate" do
    post product_spec_line_rates_path(product_specs(:bf_700)), params: { line_rate: { line_id: lines(:d1).id, kg_per_hour: "200" } }
    assert_equal 200, line_rates(:bf_700_d1).reload.kg_per_hour
  end

  test "update and reject a bad rate" do
    rate = line_rates(:bf_700_d1)
    patch product_spec_line_rate_path(rate.product_spec, rate), params: { line_rate: { kg_per_hour: "185" } }
    assert_equal 185, rate.reload.kg_per_hour

    patch product_spec_line_rate_path(rate.product_spec, rate), params: { line_rate: { kg_per_hour: "0" } }
    assert_equal 185, rate.reload.kg_per_hour
    follow_redirect!
    assert_select "#alert", /Rate must be greater than 0/
  end

  test "destroy" do
    rate = line_rates(:bf_700_d2)
    assert_difference "LineRate.count", -1 do
      delete product_spec_line_rate_path(rate.product_spec, rate)
    end
  end

  test "floor users can't change rates" do
    sign_out
    sign_in_as users(:floor)
    rate = line_rates(:bf_700_d1)
    patch product_spec_line_rate_path(rate.product_spec, rate), params: { line_rate: { kg_per_hour: "1" } }
    assert_equal 190, rate.reload.kg_per_hour
  end
end
