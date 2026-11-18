require "application_system_test_case"

class InboxRecoverySystemTest < ApplicationSystemTestCase
  test "public unread and activity badge recover through HTTP without a live inbox socket" do
    jack, eric = users(:one), users(:two)
    room = Room.create!(name: "inbox-recovery-#{SecureRandom.hex(5)}")
    room.joinables.create!(user: jack)
    room.joinables.create!(user: eric)

    # Each Chrome session starts with a clean Devise state.
    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: jack.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit rooms_path

    assert_selector '#side_panel[data-inbox-sync-connected="true"]', wait: 15
    assert_no_selector "#rooms [data-unread-room-id='#{room.id}']"

    # Simulate loss of the account-scoped ActionCable subscription while the
    # Jack tab remains visible, with no navigation or focus/visibility event.
    page.execute_script(<<~JS)
      const controller = window.Stimulus.getControllerForElementAndIdentifier(
        document.querySelector("#side_panel"), "inbox-sync"
      )
      if (!controller?.subscription) throw new Error("Inbox subscription missing")
      controller.subscription.unsubscribe()
      controller.subscription.disconnected()
    JS
    assert_selector '#side_panel[data-inbox-sync-connected="false"]', wait: 10

    incoming = room.messages.create!(user: eric, body: "Unread while inbox Cable is down")
    assert Notification.exists?(user: jack, room: room, message: incoming)

    # Only the 12-second disconnected-only HTTP fallback can update Jack's
    # still-open inbox; no F5, sender Chrome session or manual sync occurs.
    assert_selector "#rooms [data-unread-room-id='#{room.id}']", text: "1", wait: 24
    assert_selector "#notifications-nav [data-notification-unread-count='1']", wait: 10

    within "#rooms" do
      click_link room.name
    end
    assert_current_path room_path(room), ignore_query: true, wait: 10
    assert_selector "#messages-container", text: incoming.body, wait: 10
    assert_no_selector "#rooms [data-unread-room-id='#{room.id}']", wait: 10
  end
end
