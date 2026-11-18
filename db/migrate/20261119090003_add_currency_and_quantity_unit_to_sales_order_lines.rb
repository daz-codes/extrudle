# Order lines keep the currency their price was agreed in (CLAUDE.md: *_cents plus
# a currency string), so changing a customer's currency never rewrites old prices.
# They also keep the unit the quantity was entered in, so edits reopen in that unit.
class AddCurrencyAndQuantityUnitToSalesOrderLines < ActiveRecord::Migration[8.1]
  def up
    add_column :sales_order_lines, :currency, :string, null: false, default: "GBP"
    add_column :sales_order_lines, :quantity_unit, :string, null: false, default: "kg"

    execute <<~SQL
      UPDATE sales_order_lines
      SET currency = (
        SELECT customers.currency FROM sales_orders
        JOIN customers ON customers.id = sales_orders.customer_id
        WHERE sales_orders.id = sales_order_lines.sales_order_id
      )
    SQL
  end

  def down
    remove_column :sales_order_lines, :quantity_unit
    remove_column :sales_order_lines, :currency
  end
end
