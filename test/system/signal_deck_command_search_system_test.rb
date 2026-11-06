require "application_system_test_case"

class SignalDeckCommandSearchSystemTest < ApplicationSystemTestCase
  test "room discovery expands on demand and uses the existing scoped Turbo results" do
    alice = users(:one)
    visible = Room.create!(name: "Signal Deck accessible-lobby")
    hidden = Room.create!(name: "Signal Deck private-secret", is_private: true)

    login_as_browser(alice)
    visit rooms_path
    assert_selector '#room-discovery-panel[hidden]', visible: :all
    find('button[aria-label="Find public rooms"]').click
    assert_selector '#room-discovery-panel:not([hidden])'
    assert_field "Search public rooms"

    fill_in "Search public rooms", with: "Signal Deck"
    assert_selector "#search_results .room_list_item", text: visible.name, wait: 15
    assert_no_selector "#search_results .room_list_item", text: hidden.name
    find('button[aria-label="Close room search"]').click
    assert_selector '#room-discovery-panel[hidden]', visible: :all
    assert_selector '#search_results:empty', visible: :all
    assert_selector 'button[aria-label="Find public rooms"][aria-expanded="false"]'
  end

  test "message command opens on demand, accepts Ctrl K, and never clears the draft" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    room.messages.create!(user: bob, body: "Signal search verified phrase")

    login_as_browser(alice)
    visit room_path(room)
    fill_in "chat-text", with: "Keep this unsent message"
    assert_selector '#message-search-panel[hidden]', visible: :all

    find("body").send_keys([:control, "k"])
    assert_selector '#message-search-panel:not([hidden])', wait: 10
    assert_field "Search messages", visible: true
    fill_in "Search messages", with: "search verified"
    assert_selector "#message_search_results .message-search-result",
      text: "Signal search verified phrase", wait: 15

    find('input[aria-label="Search messages"]').send_keys(:escape)
    assert_selector '#message-search-panel[hidden]', visible: :all
    assert_field "chat-text", with: "Keep this unsent message"
    assert_field "Search messages", with: "", visible: :all
  end

  private

  def login_as_browser(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end
end
