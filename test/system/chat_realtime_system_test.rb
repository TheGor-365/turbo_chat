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
    assert_no_text "Invalid Email or password"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit rooms_path
    assert_current_path rooms_path, ignore_query: true
  end
end
