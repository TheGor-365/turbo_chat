require "application_system_test_case"
require "cgi"

class ChatRealtimeSystemTest < ApplicationSystemTestCase
  test "direct conversation starts from user list and stays available to both browsers" do
    alice, bob = users(:one), users(:two)
    room_name = "private_#{[alice.id, bob.id].sort.join('_')}"
    message_text = "Private two-browser delivery check"

    login_as_browser(alice)
    within "#users" do
      click_button bob.email
    end

    # Turbo form submission and 303 navigation are asynchronous in Chrome.
    # Wait for the real browser redirect before querying PostgreSQL.
    assert_current_path %r{\A/rooms/\d+\z}, ignore_query: true, wait: 10
    room = Room.find_by!(name: room_name)
    assert room.is_private?
    assert_equal [alice.id, bob.id].sort, room.participants.pluck(:user_id).sort
    assert_current_path room_path(room), ignore_query: true
    assert_selector "#single_room h4", text: bob.email
    assert_selector "#chat-text"
    assert_selector "#direct-rooms a[href='#{room_path(room)}']", text: bob.email

    Capybara.using_session(:bob) do
      login_as_browser(bob)
      assert_selector "#direct-rooms a[href='#{room_path(room)}']", text: alice.email
      within "#direct-rooms" do
        click_link alice.email
      end
      assert_current_path room_path(room), ignore_query: true
      assert_selector "#chat-text"
      assert_selector "#single_room h4", text: alice.email
    end

    fill_in "chat-text", with: message_text
    click_button "Send"
    assert_text message_text

    Capybara.using_session(:bob) do
      assert_text message_text, wait: 15
      visit rooms_path
      assert_selector "#direct-rooms a[href='#{room_path(room)}']", text: alice.email
      within "#direct-rooms" do
        click_link alice.email
      end
      assert_text message_text
    end

    assert_equal 1, room.messages.where(body: message_text).count
  end

  test "synthetic OS-style file drop reaches Rails multipart upload" do
    room = rooms(:one)
    login_as_browser(users(:one))
    visit room_path(room)
    assert_selector 'form[data-controller="message-composer"]'

    # A real DataTransfer/File/DragEvent sequence exercises the controller's
    # drop handler, distinct from native file chooser acceptance above.
    page.execute_script <<~JS
      const transfer = new DataTransfer()
      transfer.items.add(new File(["dropped content from Chrome"], "dropped.txt", { type: "text/plain" }))
      const background = document.querySelector("#messages")
      window.__dropHandled = !background.dispatchEvent(
        new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: transfer })
      )
    JS

    assert_equal true, page.evaluate_script("window.__dropHandled"), "File drop must cancel browser navigation"
    assert_selector ".composer-preview", text: "dropped.txt", wait: 5
    fill_in "chat-text", with: "Dropped an attachment"
    click_button "Send"
    assert_text "Dropped an attachment", wait: 15

    message = room.messages.find_by!(body: "Dropped an attachment")
    assert_equal 1, message.attachments.count
    assert_equal "dropped.txt", message.attachments.first.filename.to_s
    assert_selector "#message_#{message.id} a", text: "dropped.txt", wait: 15
  end

  test "Chrome drag/drop normalizes Markdown with unknown browser MIME" do
    room = rooms(:one)
    login_as_browser(users(:one))
    visit room_path(room)

    page.execute_script <<~JS
      const data = new DataTransfer()
      data.items.add(new File(["# Local readme\\n\\nHello from Markdown"], "README.md", { type: "" }))
      document.querySelector("#messages").dispatchEvent(
        new DragEvent("drop", { bubbles: true, cancelable: true, dataTransfer: data })
      )
    JS

    assert_selector ".composer-preview", text: "README.md", wait: 5
    fill_in "chat-text", with: "Markdown attachment"
    click_button "Send"

    assert_text "Markdown attachment", wait: 15
    message = room.messages.find_by!(body: "Markdown attachment")
    assert_equal "README.md", message.attachments.first.filename.to_s
    # Marcel classifies README.md as text/markdown even when the browser
    # multipart payload is normalized to text/plain; both are allowed inert text.
    assert_equal "text/markdown", message.attachments.first.blob.content_type
  end

  test "microphone denial preserves unsent text and does not attach audio" do
    login_as_browser(users(:one))
    visit room_path(rooms(:one))
    fill_in "chat-text", with: "Keep this draft"
    page.execute_script "navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException('Denied', 'NotAllowedError'))"

    click_button "Record voice message"

    assert_selector ".composer-feedback", text: /Microphone unavailable/, wait: 8
    assert_field "chat-text", with: "Keep this draft"
    assert_selector ".composer-voice", visible: false
    assert_no_selector ".composer-preview audio"
  end

  test "browser-generated Opus voice note persists and plays in second account" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    login_as_browser(alice)
    visit room_path(room)

    # Real Chrome MediaRecorder + browser-generated audio, but no OS microphone
    # dependency in CI. The owner tests the physical device later.
    page.execute_script <<~JS
      window.__audioContext = new AudioContext()
      window.__testTone = window.__audioContext.createOscillator()
      window.__audioOut = window.__audioContext.createMediaStreamDestination()
      window.__testTone.connect(window.__audioOut)
      window.__testTone.start()
      navigator.mediaDevices.getUserMedia = async (options) => {
        window.__voiceRequestedAudio = Boolean(options.audio)
        return window.__audioOut.stream
      }
    JS
    click_button "Record voice message"
    assert_selector ".composer-voice", visible: true
    assert_equal true, page.evaluate_script("window.__voiceRequestedAudio")
    sleep 1
    click_button "Stop recording"
    assert_selector ".composer-preview audio[controls]", wait: 10
    assert_selector ".composer-preview", text: /voice-.*\.webm/
    click_button "Send"

    assert_selector "#messages-container .voice-message audio[controls]", wait: 15
    message = room.messages.order(:id).last
    assert_equal 1, message.attachments.count
    assert_includes %w[audio/webm video/webm], message.attachments.first.blob.content_type

    Capybara.using_session(:bob) do
      login_as_browser(bob)
      visit room_path(room)
      assert_selector "#message_#{message.id} .voice-message audio[controls]", wait: 15
      assert_selector "#message_#{message.id} audio source[type='audio/webm']"
    end
  end

  test "camera control denies unavailable permissions without disrupting the draft" do
    login_as_browser(users(:one))
    visit room_path(rooms(:one))
    assert_selector 'button[aria-label="Take photo"]'
    assert_selector ".composer-camera", visible: false

    fill_in "chat-text", with: "My unsent draft"
    page.execute_script "navigator.mediaDevices.getUserMedia = () => Promise.reject(new DOMException('Denied', 'NotAllowedError'))"
    click_button "Take photo"
    assert_selector ".composer-feedback", text: /Camera unavailable/, wait: 8
    assert_field "chat-text", with: "My unsent draft"
    assert_selector ".composer-camera", visible: false
  end

  test "real browser file preview, removal and successful private upload" do
    room = rooms(:one)
    login_as_browser(users(:one))
    visit room_path(room)

    assert_selector 'form[data-controller="message-composer"]'
    assert_selector 'input[name="message[attachments][]"]', visible: :all
    fixture = Rails.root.join("test/fixtures/files/upload_note.txt")
    attach_file "message_attachments", fixture, make_visible: true
    assert_selector ".composer-preview", text: "upload_note.txt"
    click_button "Remove upload_note.txt"
    assert_no_selector ".composer-preview"

    attach_file "message_attachments", fixture, make_visible: true
    assert_selector ".composer-preview", text: "upload_note.txt"
    fill_in "chat-text", with: "Private document with preview"
    click_button "Send"

    assert_text "Private document with preview", wait: 15
    message = room.messages.find_by!(body: "Private document with preview")
    assert_equal 1, message.attachments.count
    assert_selector "#message_#{message.id} a", text: "upload_note.txt", wait: 15
    assert_no_selector ".composer-preview"
  end

  test "a stale browser can recover missed messages without a page reload" do
    room = rooms(:one)
    room.joinables.find_or_create_by!(user: users(:two))
    login_as_browser(users(:one))
    visit room_path(room)

    Capybara.using_session(:bob) do
      login_as_browser(users(:two))
      visit room_path(room)
      assert_selector "turbo-cable-stream-source[connected]", visible: :all, wait: 15
      page.execute_script('document.querySelector("turbo-cable-stream-source").remove()')
    end

    text = "Recover without reloading whole room"
    fill_in "chat-text", with: text
    click_button "Send"
    assert_text text, wait: 15

    Capybara.using_session(:bob) do
      assert_no_text text, wait: 2
      click_button "Sync messages"
      assert_text text, wait: 15
      assert_current_path room_path(room)
    end
  end

  test "two authenticated browsers receive the same live room message" do
    room = rooms(:one)
    room.joinables.find_or_create_by!(user: users(:two))
    message_text = "Browser realtime delivery check"

    login_as_browser(users(:one))
    visit room_path(room)
    assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"][connected]', visible: :all, wait: 15
    assert_selector "#chat-text"

    Capybara.using_session(:bob) do
      login_as_browser(users(:two))
      visit room_path(room)
      assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"][connected]', visible: :all, wait: 15
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
    assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"][connected]', visible: :all, wait: 15
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
