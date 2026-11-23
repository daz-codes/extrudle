class AddColourToCustomersAndScheduleBlocks < ActiveRecord::Migration[8.1]
  # Planner bar colours (JobColour::NAMES). Every customer has one (lime unless
  # chosen); a job's is nullable, nil meaning its customer's.
  def change
    add_column :customers, :colour, :string, default: "lime", null: false
    add_column :schedule_blocks, :colour, :string
  end
end
