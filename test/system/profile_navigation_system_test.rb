require "application_system_test_case"

class ProfileNavigationSystemTest < ApplicationSystemTestCase
  test "account settings are discoverable and the entire profile form scrolls on a short screen" do
    user = users(:one)
    page.driver.browser.manage.window.resize_to(1024, 640)

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"

    visit rooms_path
    assert_selector "body.chat-workspace"
    assert_link "Profile & settings", href: edit_user_registration_path
    assert_link "Profile settings", href: edit_user_registration_path

    click_link "Profile & settings"
    assert_current_path edit_user_registration_path, ignore_query: true
    assert_selector "h2", text: "Profile & settings"
    assert_equal "auto", page.evaluate_script("getComputedStyle(document.body).overflowY")
    assert_operator page.evaluate_script("document.documentElement.scrollHeight"),
      :>, page.evaluate_script("window.innerHeight"),
      "Profile document must exceed the short viewport and remain scrollable"

    fill_in "Display name (optional)", with: "  Gor  Demo "
    fill_in "Current password", with: "test-password-123"
    click_button "Update"

    assert_equal "Gor Demo", user.reload.display_name
    visit rooms_path
    assert_selector "#side_panel .username", text: "Gor Demo"
    assert_selector "nav[aria-label='Main navigation']", text: "Gor Demo"
  end
end
