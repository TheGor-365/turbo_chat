require "application_system_test_case"

class ConversationDiscoveryHistorySystemTest < ApplicationSystemTestCase
  test "one-to-one chats are not duplicated until explicitly searching people and history is discoverable" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob],
      "private_#{[alice.id, bob.id].sort.join('_')}")

    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: alice.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit rooms_path

    assert_no_selector "#users .sd-user-item"
    assert_selector "#direct-rooms a[href='#{room_path(room)}']", text: bob.chat_label
    assert_field "Find people by display name", visible: true
    assert_field "Search public rooms", visible: true
    assert_selector 'form.sd-people-search.sd-directory-search'
    assert_selector 'form#room_search_form.sd-directory-search'

    geometry = page.evaluate_script(<<~JS)
      (() => {
        const people = document.querySelector("form.sd-people-search").getBoundingClientRect()
        const rooms = document.querySelector("form#room_search_form").getBoundingClientRect()
        return {
          sameWidth: Math.abs(people.width - rooms.width) <= 3,
          sameHeight: Math.abs(people.height - rooms.height) <= 3,
          roomVisible: rooms.width > 160 && rooms.height >= 36,
          peopleVisible: people.width > 160 && people.height >= 36
        }
      })()
    JS
    assert_equal true, geometry.fetch("sameWidth")
    assert_equal true, geometry.fetch("sameHeight")
    assert_equal true, geometry.fetch("roomVisible")
    assert_equal true, geometry.fetch("peopleVisible")

    fill_in "Find people by display name", with: bob.chat_label
    click_button "Search people"
    assert_selector "#users .sd-user-item", text: bob.chat_label, wait: 10
    assert_selector "#direct-rooms a[href='#{room_path(room)}']", count: 1

    visit notifications_path
    assert_selector "#notification-center", wait: 10
    assert_selector "#conversation-history a[href='#{room_path(room)}']", text: bob.chat_label
    assert_selector "#chat-history-title", text: "Chat history"
    click_link "Open chat history with #{bob.chat_label}"
    assert_current_path room_path(room), ignore_query: true, wait: 10
    within("#inbox-filters") { click_link "Unread" }
    assert_current_path rooms_path(inbox: "unread"), wait: 10
    assert_selector "#empty-conversation", wait: 10
    assert_no_selector "#single_room"
  end
end
