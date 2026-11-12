require "application_system_test_case"

class HomeSignalDeckSystemTest < ApplicationSystemTestCase
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

  test "guest home provides truthful entry and working signup and login routes at mobile width" do
    page.current_window.resize_to(390, 844)
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit root_path
    assert_selector ".sd-home-hero--guest h1", text: "From conversation to an editable client brief."
    assert_selector ".sd-home-dev-note", text: /Development release candidate only/
    assert_selector ".sd-home-dev-note", text: /no public demo, SLA or paid service yet/
    assert_selector ".sd-home-dev-note", text: /AI requests require separate consent and budget controls/
    assert_selector ".sd-home-intro", text: /Save a private brief, compare versions/
    assert_selector "main a[href='https://github.com/TheGor-365/turbo_chat']", text: "View source"
    assert_no_selector ".sd-home-attention", visible: :all
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"),
      :<=, page.evaluate_script("window.innerWidth")

    within("main") { click_link "Create account" }
    assert_current_path new_user_registration_path, ignore_query: true, wait: 10
    assert_field "Email"

    visit root_path
    within("main") { click_link "Log in" }
    assert_current_path new_user_session_path, ignore_query: true, wait: 10
    assert_field "Password"
  ensure
    page.current_window.resize_to(1400, 1000)
  end

  test "signed in home lists currently joined rooms, never message snippets, and navigates to inbox" do
    alice, bob = users(:one), users(:two)
    direct = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")
    direct.messages.create!(user: bob, body: "Private Home Snippet Must Not Appear")
    outsider = User.create!(email: "home-chrome-other@example.test", password: "test-password-123")
    restricted = Room.create_private_room([bob, outsider],
      "private_#{[bob.id, outsider.id].sort.join('_')}")
    restricted.messages.create!(user: bob, body: "Restricted Home Snippet")

    fresh_login(alice)
    assert_selector ".sd-home-hero h1", text: "Pick up where you left off."
    assert_selector ".sd-home-room[href='#{room_path(direct)}']"
    assert_no_selector ".sd-home-room[href='#{room_path(restricted)}']"
    assert_no_text "Private Home Snippet Must Not Appear"
    assert_no_text "Restricted Home Snippet"
    assert_selector ".sd-home-attention[href='#{notifications_path}']"

    page.current_window.resize_to(390, 844)
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"),
      :<=, page.evaluate_script("window.innerWidth")
    theme_before = page.evaluate_script("document.documentElement.dataset.theme")
    theme_after = { "dark" => "light", "light" => "system", "system" => "dark" }.fetch(theme_before)
    find('nav button[data-theme-target="toggle"]').click
    assert_selector "html[data-theme='#{theme_after}']", visible: :all

    continue_path = URI.parse(find("main a.sd-home-button--primary", text: "Continue conversation")[:href]).path
    assert_selector ".sd-home-room[href='#{continue_path}']"
    assert_not_equal room_path(restricted), continue_path
    within("main") { click_link "Continue conversation" }
    assert_current_path continue_path, ignore_query: true, wait: 10
    assert_selector "#messages-container", wait: 10
  ensure
    page.current_window.resize_to(1400, 1000)
  end
end
