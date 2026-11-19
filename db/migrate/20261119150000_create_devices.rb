class CreateDevices < ActiveRecord::Migration[8.1]
  def change
    # A computer (one browser) an admin has approved. Its cookie holds a random
    # token; only the token's SHA-256 digest is stored.
    create_table :devices do |t|
      t.string :name, null: false
      t.string :token_digest, null: false
      t.references :approved_by, foreign_key: { to_table: :users }
      t.datetime :last_used_at
      t.string :last_ip
      t.string :user_agent
      t.datetime :revoked_at
      t.references :revoked_by, foreign_key: { to_table: :users }
      t.timestamps
      t.index :token_digest, unique: true
    end

    # Admins who can sign in from a computer that isn't approved (Stu), to approve it.
    add_column :users, :sign_in_anywhere, :boolean, null: false, default: false
  end
end
