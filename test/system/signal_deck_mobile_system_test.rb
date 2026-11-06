require "application_system_test_case"

class SignalDeckMobileSystemTest < ApplicationSystemTestCase
  test "compact viewport navigates from inbox to conversation and back without stacked panes" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    original_size = page.driver.browser.manage.window.size
    page.driver.browser.manage.window.resize_to(390, 844)

    visit new_user_session_path
    fill_in "Email", with: alice.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10

    visit rooms_path
    assert_current_path rooms_path, ignore_query: true, wait: 10
    assert_selector '#chatroom_container[data-chat-pane="inbox"]'
    assert_selector "#side_panel", visible: true
    assert_no_selector "#room_container", visible: true
    assert_operator page.evaluate_script("window.innerWidth"), :<=, 767
    assert_operator page.evaluate_script("document.documentElement.scrollWidth"),
      :<=, page.evaluate_script("window.innerWidth")

    find("#direct-rooms a[href='#{room_path(room)}']").click
    assert_current_path room_path(room), ignore_query: true, wait: 10
    assert_selector '#chatroom_container[data-chat-pane="conversation"]'
    assert_selector "#room_container #single_room", visible: true
    assert_no_selector "#side_panel", visible: true
    assert_link "Back to conversations", href: rooms_path, visible: true
    assert_field "chat-text", visible: true

    fill_in "chat-text", with: "Compact screen still delivers messages"
    click_button "Send"
    assert_selector "#messages-container > [id^='message_']",
      text: "Compact screen still delivers messages", wait: 15

    click_link "Back to conversations"
    assert_current_path rooms_path, ignore_query: true, wait: 10
    assert_selector "#side_panel", visible: true
    assert_no_selector "#room_container", visible: true
  ensure
    if original_size
      page.driver.browser.manage.window.resize_to(original_size.width, original_size.height)
    end
  end
end
