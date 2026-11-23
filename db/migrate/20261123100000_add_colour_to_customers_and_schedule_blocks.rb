class AddColourToCustomersAndScheduleBlocks < ActiveRecord::Migration[8.1]
  # Planner bar colours (JobColour::NAMES). Nullable: no colour keeps lime/lemon.
  def change
    add_column :customers, :colour, :string
    add_column :schedule_blocks, :colour, :string
  end
end
