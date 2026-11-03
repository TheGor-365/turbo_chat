require "application_system_test_case"

class ChatRealtimeSystemTest < ApplicationSystemTestCase
  test "two authenticated browsers receive the same live room message" do
    room = rooms(:one)
    room.joinables.find_or_create_by!(user: users(:two))
    message_text = "Browser realtime delivery check"

    login_as_browser(users(:one))
    visit room_path(room)
    assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"]', visible: :all
    puts "COMPOSER_GEOMETRY=" + page.evaluate_script(<<~JS)
      (() => {
        const input = document.getElementById('chat-text');
        if (!input) return JSON.stringify({missing: true});
        const ancestors = [];
        for (let e = input; e && ancestors.length < 8; e = e.parentElement) {
          const r = e.getBoundingClientRect();
          const style = getComputedStyle(e);
          ancestors.push({tag: e.tagName, id: e.id, cls: e.className.toString().slice(0, 100), x: Math.round(r.x), y: Math.round(r.y), w: Math.round(r.width), h: Math.round(r.height), display: style.display, visibility: style.visibility, overflowY: style.overflowY});
        }
        return JSON.stringify({viewport: [innerWidth, innerHeight], ancestors});
      })()
    JS
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

  private

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
