# Demo data. Idempotent: safe to run more than once (bin/rails db:seed).
# Later slices add lines, customers, specs, suppliers, POs and lots here.

DEMO_PASSWORD = "extrudle-demo"

[
  { name: "Stu Admin",   email_address: "admin@extrudle.test",  role: "admin" },
  { name: "Olivia Office", email_address: "office@extrudle.test", role: "office" },
  { name: "Fred Floor",  email_address: "floor@extrudle.test",  role: "floor" }
].each do |attrs|
  User.find_or_create_by!(email_address: attrs[:email_address]) do |user|
    user.assign_attributes(attrs.merge(password: DEMO_PASSWORD))
  end
end

puts "Seeded #{User.count} users (password: #{DEMO_PASSWORD})" unless Rails.env.test?
