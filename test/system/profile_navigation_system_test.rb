require "application_system_test_case"

class ProfileNavigationSystemTest < ApplicationSystemTestCase
  test "account settings are discoverable and the entire profile form scrolls on a short screen" do
    user = users(:one)
    # Selenium reuses its Chrome window across scenarios. Restore its dimensions
    # so the short-viewport profile test cannot clip later media controls.
    original_size = page.driver.browser.manage.window.size
    page.driver.browser.manage.window.resize_to(1024, 640)

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10

    visit rooms_path
    assert_current_path rooms_path, ignore_query: true, wait: 10
    assert_selector "body.chat-workspace"
    assert_link "Profile & settings", href: edit_user_registration_path
    assert_no_selector "#side_panel a[href=\'#{edit_user_registration_path}\']", visible: :all
    assert_selector ".sd-nav__account .sd-nav__avatar", count: 1
    assert_selector ".sd-nav__account .sd-nav__identity", text: user.chat_label

    click_link "Profile & settings"
    assert_current_path edit_user_registration_path, ignore_query: true
    assert_selector "h2", text: "Profile & settings"
    %w[Profile Security Presence Notifications].each do |heading|
      assert_selector "h3", text: heading
    end
    assert_selector "label[for=user_avatar]", text: "Choose photo"
    assert_selector "input[type=file][name=\'user[avatar]\']", visible: :all
    assert_selector ".sd-settings-delete-link", text: "Delete account"
    assert_equal "auto", page.evaluate_script("getComputedStyle(document.body).overflowY")
    assert_operator page.evaluate_script("document.documentElement.scrollHeight"),
      :>, page.evaluate_script("window.innerHeight"),
      "Profile document must exceed the short viewport and remain scrollable"

    fill_in "Display name (optional)", with: "  Gor  Demo "
    fill_in "Current password", with: "test-password-123"
    click_button "Save changes"
    # Devise submits through Turbo; wait for the redirect instead of racing
    # the asynchronous update with the database assertion.
    assert_current_path root_path, ignore_query: true, wait: 10

    assert_equal "Gor Demo", user.reload.display_name
    visit rooms_path
    assert_no_selector "#side_panel .username", visible: :all
    assert_selector ".sd-nav__account .sd-nav__identity", text: "Gor Demo"
    assert_selector "nav[aria-label='Main navigation']", text: "Gor Demo"
  ensure
    if original_size
      page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
    end
  end
end
