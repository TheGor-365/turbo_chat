require "application_system_test_case"

class SignalDeckThemeSystemTest < ApplicationSystemTestCase
  test "light dark and system themes persist across navigation without losing auth controls" do
    # A shared headless Chrome process may retain authenticated cookies and
    # appearance storage from another test's browser context.
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    page.execute_script("window.localStorage.removeItem('turbo-chat:signal-deck-theme')")
    visit root_path
    assert_selector 'nav button[data-theme-current="dark"]', wait: 10
    assert_selector 'html[data-theme="dark"]', visible: :all

    find('nav button[data-theme-target="toggle"]').click
    assert_selector 'html[data-theme="light"]', visible: :all, wait: 10
    assert_equal "light", page.evaluate_script(
      "window.localStorage.getItem('turbo-chat:signal-deck-theme')"
    )
    assert_equal "rgb(246, 248, 252)",
      page.evaluate_script("getComputedStyle(document.body).backgroundColor")

    visit new_user_session_path
    assert_selector 'html[data-theme="light"]', visible: :all
    assert_selector 'nav button[data-theme-current="light"]'
    assert_field "Email"
    page.refresh
    assert_selector 'nav button[data-theme-current="light"]', wait: 10

    find('nav button[data-theme-target="toggle"]').click
    assert_selector 'html[data-theme="system"]', visible: :all
    assert_includes %w[light dark],
      page.evaluate_script("getComputedStyle(document.documentElement).colorScheme")

    find('nav button[data-theme-target="toggle"]').click
    assert_selector 'html[data-theme="dark"]', visible: :all
    assert_equal "dark", page.evaluate_script(
      "window.localStorage.getItem('turbo-chat:signal-deck-theme')"
    )
  end
end
