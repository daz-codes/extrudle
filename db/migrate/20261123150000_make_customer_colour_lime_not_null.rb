# The first version of 20261123100000 left customers.colour nullable, and the
# preview ran it before it was changed. Bring any such database into line:
# every customer has a colour, lime unless chosen. A no-op where it's already so.
class MakeCustomerColourLimeNotNull < ActiveRecord::Migration[8.1]
  def up
    execute "UPDATE customers SET colour = 'lime' WHERE colour IS NULL OR colour = ''"
    change_column_default :customers, :colour, "lime"
    change_column_null :customers, :colour, false
  end

  def down
  end
end
