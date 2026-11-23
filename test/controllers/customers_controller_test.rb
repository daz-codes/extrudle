require "test_helper"

class CustomersControllerTest < ActionDispatch::IntegrationTest
  setup { sign_in_as users(:office) }

  test "show lists the customer's specs" do
    get customer_path(customers(:brightform))
    assert_response :success
    assert_select "a", text: "BF-700-250"
  end

  test "create" do
    assert_difference "Customer.count" do
      post customers_path, params: { customer: { name: "Westward Trays", currency: "GBP", active: "1" } }
    end
    assert_redirected_to customer_path(Customer.find_by!(name: "Westward Trays"))
  end

  test "create with errors re-renders" do
    post customers_path, params: { customer: { name: "", currency: "GBP" } }
    assert_response :unprocessable_content
    assert_select "[role=alert]", /Name can't be blank/
  end

  test "update and deactivate" do
    patch customer_path(customers(:rhine)), params: { customer: { active: "0" } }
    assert_redirected_to customer_path(customers(:rhine))
    assert_not customers(:rhine).reload.active?
  end

  test "pick a planner colour" do
    get edit_customer_path(customers(:rhine))
    assert_select "input[type=radio][name='customer[colour]']", JobColour::NAMES.size
    assert_select "input[type=radio][name='customer[colour]'][value=lime][checked]"

    patch customer_path(customers(:rhine)), params: { customer: { colour: "blackcurrant" } }
    assert_equal "blackcurrant", customers(:rhine).reload.colour
    follow_redirect!
    assert_select "dd .job-colour-blackcurrant"
  end
end
