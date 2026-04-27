class AddUsernameToUsers < ActiveRecord::Migration[8.1]
  def up
    add_column :users, :username, :string
    
    # Backfill existing users with random usernames
    User.find_each do |user|
      base = (user.first_name || user.email.split('@').first).parameterize(separator: '_')
      username = "#{base}_#{SecureRandom.hex(3)}"
      user.update_column(:username, username)
    end
    
    # Make username required
    change_column_null :users, :username, false
    add_index :users, :username, unique: true
  end
  
  def down
    remove_index :users, :username
    remove_column :users, :username
  end
end
