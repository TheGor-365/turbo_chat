require "application_system_test_case"

class PublicRoomJourneySystemTest < ApplicationSystemTestCase
  test "nonmember finds a public room, joins it, and leaves safely" do
    room = Room.create!(name: "Signal public lounge")
    user = users(:one)

    # Login must finish before Turbo navigates into public-room discovery.
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit rooms_path

    assert_no_selector "#rooms a[href='#{room_path(room)}']"
    find("button[aria-label='Find public rooms']").click
    fill_in "Search public rooms", with: "Signal public"
    assert_selector "#search_results", text: "Signal public lounge", wait: 10
    assert_no_selector "#search_results a[href='#{room_path(room)}']"
    within "#search_results" do
      find("form[action='#{join_room_path(room)}'] button[type='submit']").click
    end

    assert_current_path room_path(room), ignore_query: true, wait: 10
    assert_selector "#single_room"
    assert_equal true, room.accessible_to?(user)

    # Existing joined-room list retains its current leave action.
    within "#rooms" do
      find("form[action='#{leave_room_path(room)}'] button[type='submit']").click
    end
    assert_current_path rooms_path, ignore_query: true, wait: 10
    assert_selector '#chatroom_container[data-chat-pane="inbox"]', wait: 10
    assert_selector "#empty-conversation", wait: 10
    assert_equal false, room.accessible_to?(user)
  end

  test "two members exchange live public messages and a member can leave then rejoin" do
    room = Room.create!(name: "public-live-#{SecureRandom.hex(5)}")
    jack = users(:one)
    eric = users(:two)

    login_as_browser(jack)
    join_public_room_from_search(room)
    assert room.accessible_to?(jack)

    Capybara.using_session(:gate1_eric) do
      login_as_browser(eric)
      join_public_room_from_search(room)
      assert room.accessible_to?(eric)
    end

    fill_in "chat-text", with: "Jack sends to live public room"
    click_button "Send"
    assert_selector "#messages-container > [id^='message_']",
      text: "Jack sends to live public room", wait: 15

    Capybara.using_session(:gate1_eric) do
      # No reload: the independently authenticated browser receives Cable.
      assert_selector "#messages-container > [id^='message_']",
        text: "Jack sends to live public room", wait: 15
      fill_in "chat-text", with: "Eric replies in public room"
      click_button "Send"
      assert_selector "#messages-container > [id^='message_']",
        text: "Eric replies in public room", wait: 15
    end

    assert_selector "#messages-container > [id^='message_']",
      text: "Eric replies in public room", wait: 15
    assert_equal 2, room.messages.count

    Capybara.using_session(:gate1_eric) do
      within("#rooms") do
        find("form[action='#{leave_room_path(room)}'] button[type='submit']", text: "Leave").click
      end
      assert_current_path rooms_path, ignore_query: true, wait: 10
      assert_no_selector "#rooms a[href='#{room_path(room)}']"
      assert_not room.accessible_to?(eric)
    end

    # Membership changes never delete the room or its existing history.
    assert room.accessible_to?(jack)
    assert_equal 2, room.messages.count

    Capybara.using_session(:gate1_eric) do
      join_public_room_from_search(room)
      assert room.accessible_to?(eric)
      assert_selector "#messages-container > [id^='message_']",
        text: "Jack sends to live public room", wait: 15
    end

    fill_in "chat-text", with: "Jack after Eric rejoined"
    click_button "Send"
    assert_selector "#messages-container > [id^='message_']",
      text: "Jack after Eric rejoined", wait: 15

    Capybara.using_session(:gate1_eric) do
      assert_selector "#messages-container > [id^='message_']",
        text: "Jack after Eric rejoined", wait: 15
    end
    assert_equal 3, room.messages.count
  end

  private

  def join_public_room_from_search(room)
    visit rooms_path
    find("button[aria-label='Find public rooms']").click
    fill_in "Search public rooms", with: room.name
    assert_selector "#search_results", text: room.name, wait: 15
    within("#search_results") do
      find("form[action='#{join_room_path(room)}'] button[type='submit']").click
    end
    assert_current_path room_path(room), ignore_query: true, wait: 10
    assert_selector "#single_room"
    assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"][connected]',
      visible: :all, wait: 15
  end

  def login_as_browser(user)
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
end
