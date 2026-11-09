require "application_system_test_case"

class AccountAuthSignalDeckSystemTest < ApplicationSystemTestCase
  def fresh_login(user)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  test "Signal Deck auth routes are keyboard-friendly and show a failed login without losing fields" do
    page.current_window.resize_to(390, 844)
    visit new_user_session_path
    assert_selector ".sd-auth-page .sd-auth-heading h1", text: "Log in"
    assert_selector "input#user_email[autocomplete='email']"
    assert_selector "input#user_password[autocomplete='current-password']"
    assert_selector ".sd-auth-remember input[type=checkbox]"
    assert_equal "0px", page.evaluate_script(
      "getComputedStyle(document.querySelector('#user_email')).borderTopWidth")
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"),
      :<=, page.evaluate_script("window.innerWidth")

    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "wrong-password-123"
    click_button "Log in"
    assert_selector ".sd-auth-feedback[role='alert']", wait: 10
    assert_selector "h1", text: "Log in"

    click_link "Sign up"
    assert_current_path new_user_registration_path, ignore_query: true, wait: 10
    assert_selector "h1", text: "Sign up"
    assert_selector "input#user_email"
    assert_selector "input#user_avatar[type=file]", visible: :all
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"),
      :<=, page.evaluate_script("window.innerWidth")

    click_link "Log in"
    assert_current_path new_user_session_path, ignore_query: true, wait: 10
    click_link "Forgot your password?"
    assert_current_path new_user_password_path, ignore_query: true, wait: 10
    assert_selector "h1", text: "Forgot your password?"
    assert_field "Email"
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "profile keeps scrollable sections, current password, theme and mobile layout" do
    fresh_login(users(:one))
    visit edit_user_registration_path
    assert_selector ".sd-account-settings .sd-account-heading h2", text: "Profile & settings"
    assert_selector ".sd-account-settings #profile-settings-title", text: "Profile"
    assert_selector ".sd-account-settings #security-settings-title", text: "Security"
    assert_selector ".sd-account-settings #presence-privacy-title", text: "Presence"
    assert_selector ".sd-account-settings #notification-settings-title", text: "Notifications"
    assert_selector ".sd-account-settings #account-removal-title", text: "Account removal"
    assert_selector "input#user_current_password[autocomplete='current-password']"
    assert_selector "label[for=user_avatar]", text: "Choose photo"
    assert_no_selector ".sd-account-settings .card.border-secondary", visible: :all

    page.current_window.resize_to(390, 720)
    assert_equal "auto", page.evaluate_script("getComputedStyle(document.body).overflowY")
    assert_operator page.evaluate_script("document.documentElement.scrollHeight"),
      :>, page.evaluate_script("window.innerHeight")
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"),
      :<=, page.evaluate_script("window.innerWidth")
    assert_equal "0px", page.evaluate_script(
      "getComputedStyle(document.querySelector('#user_email')).borderTopWidth")
    theme_before = page.evaluate_script("document.documentElement.dataset.theme")
    theme_after = { "dark" => "light", "light" => "system", "system" => "dark" }.fetch(theme_before)
    find('nav button[data-theme-target="toggle"]').click
    assert_selector "html[data-theme='#{theme_after}']", visible: :all
    assert_field "Current password"
    assert_selector "#presence-visibility-toggle"
    assert_selector ".sd-settings-delete-link", text: "Delete account"
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
