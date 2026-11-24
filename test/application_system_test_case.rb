require "test_helper"

# Chrome 158 refuses the origin "*" that Capybara 3.40 sends to
# Storage.clearDataForOrigin when it resets the session between tests. Clear
# the cookies and the app's own storage another way instead. Remove this once
# Capybara sends a real origin.
module ClearStorageWithoutWildcardOrigin
  def execute_cdp(cmd, **args)
    super
  rescue Selenium::WebDriver::Error::InvalidArgumentError => e
    raise unless cmd == "Storage.clearDataForOrigin" && args[:origin] == "*" && e.message.include?("not a valid URL")

    super("Network.clearBrowserCookies")
    super(cmd, **args, origin: Capybara.current_session.server.base_url) if Capybara.current_session.server
  end
end
Capybara::Selenium::Driver::ChromeDriver.prepend(ClearStorageWithoutWildcardOrigin)

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  # Find icon buttons (▲ ▼ ✕) by their accessible names.
  Capybara.enable_aria_label = true

  # Chrome's password-manager and breached-password popups steal clicks after sign-in.
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1000 ] do |options|
    options.add_preference("credentials_enable_service", false)
    options.add_preference("profile.password_manager_enabled", false)
    options.add_preference("profile.password_manager_leak_detection", false)
    options.add_argument("--disable-features=PasswordLeakDetection,PasswordManagerOnboarding")
  end

  def sign_in(user, password: "password")
    visit new_session_path
    fill_in "Email address", with: user.email_address
    fill_in "Password", with: password
    click_on "Sign in"
    # The first sign-in after the server boots can be slow (bcrypt, cold
    # caches); waiting longer here stops it failing now and then.
    assert_no_current_path new_session_path, wait: 10
    wait_for_turbo
  end

  # Turbo sets aria-busy on <html> while a visit or form submission is in flight.
  # Clicking during that window can be swallowed, so wait for it to clear.
  def wait_for_turbo
    assert_no_selector "html[aria-busy]", visible: :all
  end
end
