require "application_system_test_case"

class MessageRevisionRecoverySystemTest < ApplicationSystemTestCase
  test "missed edits and deletes recover without reloading the conversation" do
    jack, eric = users(:one), users(:two)
    room = Room.create!(name: "revisions-during-reconnect-#{SecureRandom.hex(4)}")
    room.joinables.create!(user: jack)
    room.joinables.create!(user: eric)
    edited = room.messages.create!(user: jack, body: "Edit-before-disconnect")
    deleted = room.messages.create!(user: jack, body: "Delete-before-disconnect")

    Capybara.current_session.reset!
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 10
    fill_in "Email", with: eric.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit room_path(room)

    assert_selector "#message_#{edited.id}", text: "Edit-before-disconnect", wait: 15
    assert_selector "#message_#{deleted.id}", text: "Delete-before-disconnect", wait: 10
    assert_selector "turbo-cable-stream-source[channel='RoomMessagesChannel'][connected]",
      visible: :all, wait: 15

    # Keep Eric's room visible but deliberately remove its live message stream.
    # Only the explicit authenticated HTTP Sync can reconcile these revisions.
    page.execute_script(<<~JS)
      const source = document.querySelector(
        "turbo-cable-stream-source[channel='RoomMessagesChannel']"
      )
      if (!source) throw new Error("Expected room stream")
      source.remove()
    JS

    edited.update!(body: "Edit-after-disconnect", updated_at: edited.updated_at + 1.second)
    deleted.destroy!
    assert_selector "#message_#{edited.id}", text: "Edit-before-disconnect"
    assert_selector "#message_#{deleted.id}", text: "Delete-before-disconnect"

    click_button "Sync messages"
    assert_selector "#message_#{edited.id}", text: "Edit-after-disconnect", wait: 15
    assert_no_selector "#message_#{edited.id}", text: "Edit-before-disconnect", wait: 10
    assert_no_selector "#message_#{deleted.id}", wait: 10
    assert_current_path room_path(room), ignore_query: true
  end
end
