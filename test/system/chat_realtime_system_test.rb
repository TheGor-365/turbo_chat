require "application_system_test_case"
require "cgi"

class ChatRealtimeSystemTest < ApplicationSystemTestCase
  test "two authenticated browsers receive the same live room message" do
    room = rooms(:one)
    room.joinables.find_or_create_by!(user: users(:two))
    message_text = "Browser realtime delivery check"

    login_as_browser(users(:one))
    visit room_path(room)
    assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"]', visible: :all
    assert_selector "#chat-text"

    Capybara.using_session(:bob) do
      login_as_browser(users(:two))
      visit room_path(room)
      assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"]', visible: :all
      assert_selector "#chat-text"
    end

    fill_in "chat-text", with: message_text
    click_button "Send"
    assert_text message_text

    Capybara.using_session(:bob) do
      assert_text message_text, wait: 15
    end

    assert_equal 1, room.messages.where(body: message_text).count
  end

  test "revoked room membership does not receive broadcasts and reconnect requires rejoin" do
    room = rooms(:one)
    room.joinables.find_or_create_by!(user: users(:two))

    login_as_browser(users(:one))
    visit room_path(room)
    assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"]', visible: :all
    assert_selector "#chat-text"

    Capybara.using_session(:bob) do
      login_as_browser(users(:two))
      visit room_path(room)
      assert_selector "#chat-text"
    end

    # A second authenticated HTTP client changes the membership while Alice
    # keeps the original room page and WebSocket open in Chrome.
    membership_client = ActionDispatch::Integration::Session.new(Rails.application)
    membership_client.get new_user_session_path
    login_token = csrf_token_from(membership_client.response.body)
    membership_client.post user_session_path, params: {
      user: { email: users(:one).email, password: "test-password-123" }
    }, headers: { "X-CSRF-Token" => login_token }
    assert membership_client.response.redirect?

    membership_client.get rooms_path
    mutation_token = csrf_token_from(membership_client.response.body)
    membership_client.delete leave_room_path(room), headers: { "X-CSRF-Token" => mutation_token }
    assert membership_client.response.redirect?
    assert_not room.joinables.exists?(user: users(:one))

    after_leave = "After leave private delivery check"
    Capybara.using_session(:bob) do
      fill_in "chat-text", with: after_leave
      click_button "Send"
      assert_text after_leave
    end

    # The stale Alice tab must not receive any post-revocation event.
    assert_no_text after_leave, wait: 3
    visit room_path(room)
    assert_no_selector "#chat-text"

    membership_client.post join_room_path(room), headers: { "X-CSRF-Token" => mutation_token }
    assert membership_client.response.redirect?
    visit room_path(room)
    assert_selector "#chat-text"
    assert_text after_leave

    after_rejoin = "After rejoin realtime delivery check"
    Capybara.using_session(:bob) do
      fill_in "chat-text", with: after_rejoin
      click_button "Send"
      assert_text after_rejoin
    end
    assert_text after_rejoin, wait: 15
  end

  test "message edit and deletion propagate between two independent browsers" do
    room = rooms(:one)
    room.joinables.find_or_create_by!(user: users(:two))
    original = "Message before author edit"
    edited = "Message after author edit"

    login_as_browser(users(:one))
    visit room_path(room)
    assert_selector "#chat-text"

    Capybara.using_session(:bob) do
      login_as_browser(users(:two))
      visit room_path(room)
      assert_selector "#chat-text"
    end

    fill_in "chat-text", with: original
    click_button "Send"
    assert_text original
    message = room.messages.find_by!(body: original)

    Capybara.using_session(:bob) do
      assert_selector "#message_#{message.id}", text: original, wait: 15
      assert_no_selector "#message_#{message.id} a", text: "Edit"
    end

    within "#message_#{message.id}" do
      click_link "Edit"
    end
    assert_current_path edit_room_message_path(room, message)
    fill_in "Message", with: edited
    click_button "Save changes"
    assert_current_path room_path(room)
    assert_selector "#message_#{message.id}", text: edited, wait: 15

    Capybara.using_session(:bob) do
      assert_selector "#message_#{message.id}", text: edited, wait: 15
      assert_no_selector "#message_#{message.id}", text: original
    end

    within "#message_#{message.id}" do
      accept_confirm { click_button "Delete" }
    end
    assert_no_selector "#message_#{message.id}", wait: 15
    Capybara.using_session(:bob) do
      assert_no_selector "#message_#{message.id}", wait: 15
    end
    assert_not Message.exists?(message.id)
  end

  test "CSRF protection rejects a browser-style room mutation without a token" do
    assert ActionController::Base.allow_forgery_protection,
      "System tests must run with CSRF protection enabled"

    browser_client = ActionDispatch::Integration::Session.new(Rails.application)
    browser_client.get new_user_session_path
    token = csrf_token_from(browser_client.response.body)
    browser_client.post user_session_path, params: {
      user: { email: users(:one).email, password: "test-password-123" }
    }, headers: { "X-CSRF-Token" => token }
    assert browser_client.response.redirect?

    browser_client.post rooms_path, params: { room: { name: "forged-csrf-room" } }
    assert_includes [403, 422], browser_client.response.status
    assert_not Room.exists?(name: "forged-csrf-room")
  end

  private

  def csrf_token_from(html)
    token = html.match(/<meta name="csrf-token" content="([^"]+)"/)&.captures&.first
    assert token.present?, "Expected a Rails CSRF meta token in authenticated HTML"
    CGI.unescapeHTML(token)
  end

  def login_as_browser(user)
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit rooms_path
    assert_current_path rooms_path, ignore_query: true
  end
end
