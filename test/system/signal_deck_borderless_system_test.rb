require "application_system_test_case"

class SignalDeckBorderlessSystemTest < ApplicationSystemTestCase
  test "desktop workspace uses quiet icons and tokenized bubble surfaces in both themes" do
    room = Room.create_private_room([users(:one), users(:two)], "private_#{[users(:one).id, users(:two).id].sort.join('_')}")
    own = room.messages.create!(user: users(:one), body: "Signal Deck low-chroma bubble")
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: users(:one).email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit room_path(room)
    assert_current_path room_path(room), ignore_query: true, wait: 10

    assert_selector ".sd-conversation-header", visible: true
    assert_selector ".sd-conversation-toolbar", visible: true
    assert_selector '.sd-conversation-toolbar button[aria-label="Search messages"]'
    assert_no_selector '.sd-conversation-toolbar button[aria-label="Sync messages"]', visible: true
    click_button "Conversation tools"
    assert_selector '.sd-conversation-toolbar button[aria-label="Sync messages"]'
    assert_selector '.sd-conversation-toolbar button[aria-label="Mute alerts"]'
    assert_selector '.sd-conversation-toolbar [aria-label="Conversation presence"]'
    assert_selector "#message_#{own.id} .sd-message-bubble"
    assert_selector "button[aria-label='Send']"
    assert_field "chat-text"
    assert_equal "0px", page.evaluate_script("getComputedStyle(document.querySelector('.sd-message-bubble')).borderTopWidth")
    assert_equal "0px", page.evaluate_script("getComputedStyle(document.querySelector('.sd-message-composer')).borderTopWidth")
    assert_equal "0px", page.evaluate_script("getComputedStyle(document.querySelector('.sd-nav')).borderBottomWidth")
    assert_operator page.evaluate_script("parseFloat(getComputedStyle(document.querySelector('#room_container')).paddingTop)"), :>=, 12

    find('nav button[data-theme-target="toggle"]').click
    assert_selector 'html[data-theme="light"]', visible: :all
    assert_equal "0px", page.evaluate_script("getComputedStyle(document.querySelector('.sd-message-composer')).borderTopWidth")
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"), :<=, page.evaluate_script("window.innerWidth")
  end
end
