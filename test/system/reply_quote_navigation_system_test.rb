require "application_system_test_case"

class ReplyQuoteNavigationSystemTest < ApplicationSystemTestCase
  test "reply quote opens unloaded earlier message in the inner history pane" do
    user = users(:one)
    # An isolated public room keeps history ordering independent from shared
    # fixture messages and unrelated realtime test activity.
    room = Room.create!(name: "reply-focus-test-#{SecureRandom.hex(4)}")
    room.joinables.create!(user: user)
    original = room.messages.create!(user: user, body: "Original early message #{SecureRandom.hex(4)}")
    13.times { |i| room.messages.create!(user: user, body: "Intermediate message #{i}") }
    reply = room.messages.create!(user: user, body: "Reply to the early message", reply_to: original)
    assert_equal original.id, reply.reload.reply_to_id
    assert_equal reply.id, room.messages.order(created_at: :desc, id: :desc).first.id

    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    visit room_path(room)

    assert_selector "#message_#{reply.id} .message-quote-link"
    assert_no_selector "#message_#{original.id}"
    within "#message_#{reply.id}" do
      find(".message-quote-link").click
    end

    assert_selector "#message_#{original.id}.message-focused", wait: 10
    assert_selector ".message-focus-banner", text: /Viewing an older message/
    assert_equal "", page.evaluate_script("window.location.hash")
    click_link "Return to latest messages"
    assert_no_selector ".message-focus-banner"
    assert_selector "#message_#{reply.id}"
  end
end
