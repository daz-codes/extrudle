# What Stu's paper plans (5.4.1.1, 16 Nov 2026) showed we were missing. All new
# columns are optional or default to today's behaviour, so existing data is unchanged.
class AddPaperPlanFields < ActiveRecord::Migration[8.1]
  def change
    # A line's usual rate, for specs with no rate of their own on it (§11 Q89).
    add_column :lines, :default_kg_per_hour, :integer
    add_check_constraint :lines, "default_kg_per_hour IS NULL OR default_kg_per_hour > 0", name: "lines_default_rate_positive"

    # "Required w/c 30/11/26": any day that week, required_on being its Monday (§11 Q90).
    add_column :sales_orders, :required_week, :boolean, default: false, null: false
    # Leeway's "Cinderford – P20424": the customer's site this order goes to (§11 Q91).
    add_column :sales_orders, :delivery_site, :string

    # "Anti Fog 2%" (§11 Q93), in basis points like silicone.
    add_column :product_specs, :antifog_bp, :integer
    add_check_constraint :product_specs, "antifog_bp IS NULL OR (antifog_bp > 0 AND antifog_bp <= 10000)", name: "product_specs_antifog_range"
  end
end
