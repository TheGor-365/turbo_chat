require "application_system_test_case"

class PublicRoomJourneySystemTest < ApplicationSystemTestCase
  test "nonmember finds a public room, joins it, and leaves safely" do
    room = Room.create!(name: "Signal public lounge")
    user = users(:one)

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
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
    assert_equal false, room.accessible_to?(user)
  end
end
