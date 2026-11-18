# Demo data. Idempotent: safe to run more than once (bin/rails db:seed).
# Later slices add lines, customers, specs, suppliers, POs and lots here.
#
# Production never gets the demo users (their password is in this repo).
# Kamal runs db:prepare, which seeds a fresh database, so in production we only
# create the first admin, and only from ADMIN_EMAIL / ADMIN_PASSWORD.

if Rails.env.production?
  email, password = ENV["ADMIN_EMAIL"], ENV["ADMIN_PASSWORD"]

  if email.present? && password.present?
    User.find_or_create_by!(email_address: email) do |user|
      user.assign_attributes(name: ENV.fetch("ADMIN_NAME", "Admin"), role: "admin", password: password)
    end
    puts "Ensured admin user #{email}"
  else
    puts "Skipping seeds in production. Set ADMIN_EMAIL and ADMIN_PASSWORD to create the first admin."
  end
  return
end

DEMO_PASSWORD = "extrudle-demo"

[
  { name: "Stu Kershaw",  email_address: "admin@extrudle.test",  role: "admin" },
  { name: "Jess Kershaw", email_address: "office@extrudle.test", role: "office" },
  { name: "Eric Kershaw", email_address: "floor@extrudle.test",  role: "floor" }
].each do |attrs|
  User.find_or_create_by!(email_address: attrs[:email_address]) do |user|
    user.assign_attributes(attrs.merge(password: DEMO_PASSWORD))
  end
end

puts "Seeded #{User.count} users (password: #{DEMO_PASSWORD})" unless Rails.env.test?
