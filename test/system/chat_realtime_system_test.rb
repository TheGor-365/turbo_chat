require "application_system_test_case"
require "cgi"

class ChatRealtimeSystemTest < ApplicationSystemTestCase
  test "mute and unmute only future notification events without blocking live messages" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")

    login_as_browser(alice)
    visit room_path(room)
    within("#room-notification-preference") { click_button "Mute alerts" }
    assert_selector "#room-notification-preference", text: "Unmute alerts", wait: 10
    visit rooms_path

    Capybara.using_session(:muted_bob) do
      login_as_browser(bob)
      visit room_path(room)
      fill_in "chat-text", with: "Muted message delivered to conversation"
      click_button "Send"
      assert_selector "#messages-container", text: "Muted message delivered to conversation", wait: 10
    end

    assert_selector "#direct-rooms [data-unread-room-id='#{room.id}']", text: "1", wait: 15
    assert_no_selector "#notifications-nav [data-notification-unread-count]", wait: 5

    visit room_path(room)
    assert_selector "#messages-container", text: "Muted message delivered to conversation", wait: 10
    muted_message = room.messages.find_by!(body: "Muted message delivered to conversation")
    assert_read_cursor(room: room, user: alice, expected_id: muted_message.id)
    within("#room-notification-preference") { click_button "Unmute alerts" }
    assert_selector "#room-notification-preference", text: "Mute alerts", wait: 10
    visit rooms_path

    Capybara.using_session(:muted_bob) do
      fill_in "chat-text", with: "Unmuted message has an activity alert"
      click_button "Send"
      assert_selector "#messages-container", text: "Unmuted message has an activity alert", wait: 10
    end

    assert_selector "#notifications-nav [data-notification-unread-count='1']", wait: 15
    assert_selector "#direct-rooms [data-unread-room-id='#{room.id}']", text: "1", wait: 15
  end

  test "account invisible mode masks existing DM presence across other tabs without reloading" do
    nonce = SecureRandom.hex(5)
    alice = User.create!(email: "privacy-ui-alice-#{nonce}@example.test", password: "test-password-123")
    bob = User.create!(email: "privacy-ui-bob-#{nonce}@example.test", password: "test-password-123")
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")

    login_as_browser(bob)
    visit room_path(room)
    assert_selector '#single_room[data-peer-presence-connected="true"]', wait: 15

    Capybara.using_session(:privacy_alice_chat) do
      login_as_browser(alice)
      visit room_path(room)
      assert_selector '#single_room[data-peer-presence-connected="true"]', wait: 15
    end
    assert_selector '#single_room[data-peer-presence-status="online"]', wait: 15

    # Keep the Alice DM open in one tab and toggle the account preference in
    # a second tab. Bob must not need to reload to observe the privacy change.
    Capybara.using_session(:privacy_alice_settings) do
      login_as_browser(alice)
      visit edit_user_registration_path
      assert_selector "#presence-privacy-settings", text: /Current setting: Show when active/
      assert_selector "#presence-visibility-toggle[value='Appear offline']", wait: 10
      within("#presence-privacy-settings") { click_button "Appear offline" }
      assert_selector "#presence-privacy-settings", text: /Current setting: Appear offline/, wait: 10
    end
    assert_selector '#single_room[data-peer-presence-status="offline"]', wait: 15

    Capybara.using_session(:privacy_alice_chat) do
      page.execute_script(<<~JS)
        window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("#single_room"), "peer-presence"
        ).heartbeat()
      JS
    end
    assert_selector '#single_room[data-peer-presence-status="offline"]', wait: 10

    Capybara.using_session(:privacy_alice_settings) do
      within("#presence-privacy-settings") { click_button "Show when active" }
      assert_selector "#presence-privacy-settings", text: /Current setting: Show when active/, wait: 10
    end
    Capybara.using_session(:privacy_alice_chat) do
      page.execute_script(<<~JS)
        window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("#single_room"), "peer-presence"
        ).heartbeat()
      JS
    end
    assert_selector '#single_room[data-peer-presence-status="online"]', wait: 15
  end

  test "private presence is live, scoped, and remains online while another session is connected" do
    # Use unique identities: previous realtime scenarios may leave fixture-user
    # WebSocket subscriptions alive briefly after the browser test ends.
    alice = User.create!(email: "presence-alice-#{SecureRandom.hex(5)}@example.test", password: "test-password-123")
    bob = User.create!(email: "presence-bob-#{SecureRandom.hex(5)}@example.test", password: "test-password-123")
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/4"))
    [alice, bob].each do |user|
      prefix = "turbo-chat:#{Rails.env}:presence:v1:room:#{room.id}:user:#{user.id}"
      redis.del("#{prefix}:sessions", "#{prefix}:visible")
    end
    redis.close

    login_as_browser(alice)
    visit room_path(room)
    assert_selector '#single_room[data-peer-presence-connected="true"]', wait: 15
    assert_selector '#single_room[data-peer-presence-status="offline"]', wait: 10

    Capybara.using_session(:presence_bob_one) do
      login_as_browser(bob)
      visit room_path(room)
      assert_selector '#single_room[data-peer-presence-connected="true"]', wait: 15
    end
    assert_selector '#single_room[data-peer-presence-status="online"]', wait: 15
    assert_selector ".peer-presence", text: "Online in this chat"

    Capybara.using_session(:presence_bob_two) do
      login_as_browser(bob)
      visit room_path(room)
      assert_selector '#single_room[data-peer-presence-connected="true"]', wait: 15
    end
    assert_presence_session_count(room: room, user: bob, expected: 2)
    Capybara.using_session(:presence_bob_one) do
      # Explicit ActionCable unsubscribe is the deterministic clean-exit path.
      # Abrupt browser disappearance is covered by PresenceRegistry TTL tests.
      page.execute_script(<<~JS)
        window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("#single_room"), "peer-presence"
        ).subscription.unsubscribe()
      JS
      assert_presence_session_count(room: room, user: bob, expected: 1)
      visit rooms_path
    end
    assert_selector '#single_room[data-peer-presence-status="online"]', wait: 10

    Capybara.using_session(:presence_bob_two) do
      page.execute_script(<<~JS)
        window.Stimulus.getControllerForElementAndIdentifier(
          document.querySelector("#single_room"), "peer-presence"
        ).subscription.unsubscribe()
      JS
      assert_presence_session_count(room: room, user: bob, expected: 0)
      visit rooms_path
    end
    assert_selector '#single_room[data-peer-presence-status="offline"]', wait: 15
    assert_selector ".peer-presence", text: "Offline"
  end

  test "private typing indicator follows live input and expires on stop without persisting text" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    initial_count = room.messages.count

    login_as_browser(alice)
    visit room_path(room)
    assert_selector '#single_room[data-typing-indicator-connected="true"]', wait: 15
    assert_selector "#typing-indicator", visible: false

    Capybara.using_session(:bob) do
      login_as_browser(bob)
      visit room_path(room)
      assert_selector '#single_room[data-typing-indicator-connected="true"]', wait: 15
      fill_in "chat-text", with: "Draft must remain private"
    end

    assert_selector "#typing-indicator", text: "Other participant is typing", wait: 10

    # Losing input focus (including switching browser windows) must not
    # instantly erase the recipient's short-lived indication. It naturally
    # clears after inactivity; explicit draft clearing still sends "stopped".
    Capybara.using_session(:bob) do
      page.execute_script("document.querySelector('#chat-text').blur()")
    end
    assert_selector "#typing-indicator", text: "Other participant is typing", wait: 1

    Capybara.using_session(:bob) do
      fill_in "chat-text", with: ""
    end
    assert_selector "#typing-indicator", visible: false, wait: 10
    assert_equal initial_count, room.messages.count
    assert_not_includes page.body, "Draft must remain private"
  end

  test "opening a historical search result does not clear unread newer messages" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    older = room.messages.create!(user: bob, body: "Historical result to inspect")
    13.times { |i| room.messages.create!(user: bob, body: "Unread after historical hit #{i}") }
    newest = room.messages.order(:id).last

    login_as_browser(alice)
    visit room_path(room, focus: older.id)
    assert_selector '#single_room[data-room-read-history-focus-value="true"]'
    assert_selector "#message_#{older.id}"
    assert_selector "#direct-rooms [data-unread-room-id='#{room.id}']", text: "14"

    # The read controller normally sends a POST after a 300ms debounce.
    # A focused historical page must not send that acknowledgement.
    sleep 0.8
    assert_nil ConversationReadState.find_by(room: room, user: alice)
    assert_selector "#direct-rooms [data-unread-room-id='#{room.id}']", text: "14"

    click_link "Return to latest messages"
    assert_selector '#single_room[data-room-read-history-focus-value="false"]'
    assert_selector "#message_#{newest.id}"
    assert_no_selector "#direct-rooms [data-unread-room-id='#{room.id}']", wait: 10
    assert_read_cursor(room: room, user: alice, expected_id: newest.id)
  end

  test "typing channel is absent from public rooms" do
    login_as_browser(users(:one))
    visit room_path(rooms(:one))
    assert_no_selector '[data-controller~="typing-indicator"]', visible: :all
    assert_no_selector "#typing-indicator", visible: :all
  end

  test "reply action works for a message appended after the room loads" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")

    login_as_browser(alice)
    visit room_path(room)
    assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"][connected]',
      visible: :all, wait: 15
    fill_in "chat-text", with: "Keep this unfinished draft"

    Capybara.using_session(:bob) do
      login_as_browser(bob)
      visit room_path(room)
      fill_in "chat-text", with: "Arrived after initial page"
      click_button "Send"
      # Assert a persisted, broadcast message DOM element, not text that may
      # still exist in the input field before the async Turbo POST completes.
      assert_selector "#messages-container > [id^='message_']", text: "Arrived after initial page", wait: 15
    end
    incoming = room.messages.find_by!(body: "Arrived after initial page")
    assert_selector "#message_#{incoming.id}", text: incoming.body, wait: 15

    within "#message_#{incoming.id}" do
      click_button "Message actions"
      click_button "Reply"
    end
    assert_selector ".composer-reply", text: /Arrived after initial page/
    assert_field "chat-text", with: "Keep this unfinished draft"
    assert_equal incoming.id.to_s, find('input[name="message[reply_to_id]"]', visible: :all).value
    click_button "Send"
    assert_selector "#messages-container > [id^='message_']",
      text: "Keep this unfinished draft", wait: 15

    reply = room.messages.find_by!(body: "Keep this unfinished draft")
    assert_equal incoming.id, reply.reply_to_id
    Capybara.using_session(:bob) do
      assert_selector "#message_#{reply.id} .message-quote", text: /Arrived after initial page/, wait: 15
    end
  end

  test "search finds an old message and navigates to it in a paginated room" do
    room = rooms(:one)
    12.times { |i| room.messages.create!(user: users(:one), body: "Historical context #{i} " + ("padding " * 40)) }
    older = room.messages.create!(user: users(:one), body: "unique searchable old quote")
    17.times { |i| room.messages.create!(user: users(:one), body: "Recent ordinary note #{i}") }

    login_as_browser(users(:one))
    visit room_path(room)
    assert_no_selector "#message_#{older.id}"
    fill_in "chat-text", with: "Keep private draft during search"
    assert_selector '#message-search-panel[hidden]', visible: :all
    find('button[aria-label="Search messages"]').click
    within ".message-search-form" do
      assert_no_button "Search"
    end
    fill_in "Search messages", with: "unique searchable"
    # No click or Enter: debounced live search populates an overlay.
    assert_selector "turbo-frame#message_search_results .message-search-result",
      text: /unique searchable old quote/, wait: 10
    assert_selector "turbo-frame#message_search_results mark.message-search-highlight",
      text: "unique searchable"
    assert_field "chat-text", with: "Keep private draft during search"
    within "turbo-frame#message_search_results" do
      find("a.message-search-hit[href*=\"focus=#{older.id}\"]").click
    end
    assert_selector "#message_#{older.id}.message-focused", text: older.body, wait: 10
    assert_selector ".message-focus-banner", text: /Viewing an older message/
    assert_selector "a.message-jump-latest", text: "Latest messages"
    assert_equal "", page.evaluate_script("window.location.hash"),
      "Message navigation must not use a browser-native fragment jump"
    assert_in_delta 0, page.evaluate_script("window.scrollY"), 2,
      "Focused message should scroll only within #messages, not the whole page"
    sleep 0.35
    assert_operator page.evaluate_script("document.querySelector('#messages').scrollTop"), :>, 0,
      "Long history should smoothly scroll the inner chat pane"
    assert_selector "#single_room h4", visible: true
    click_link "Return to latest messages"
    assert_no_selector ".message-focus-banner"
    assert_selector "#messages-container > [id^='message_']", wait: 10
  end

  test "history view Escape and floating latest shortcut return to current conversation" do
    room = rooms(:one)
    14.times { |i| room.messages.create!(user: users(:one), body: "Older chat entry #{i} " + ("context " * 20)) }
    target = room.messages.order(:id).first
    login_as_browser(users(:one))
    visit room_path(room, focus: target.id)
    assert_selector ".message-focus-banner", text: "Viewing an older message"
    assert_selector "a.message-jump-latest", visible: true
    find("a.message-jump-latest").click
    assert_current_path room_path(room), ignore_query: true
    assert_no_selector ".message-focus-banner"

    visit room_path(room, focus: target.id)
    assert_selector ".message-focus-banner"
    page.execute_script("document.dispatchEvent(new KeyboardEvent('keydown', {key: 'Escape', bubbles: true}))")
    assert_current_path room_path(room), ignore_query: true
    assert_no_selector ".message-focus-banner"
  end

  test "scrolling up reveals a floating latest shortcut and smoothly returns without navigation" do
    room = rooms(:one)
    10.times { |i| room.messages.create!(user: users(:one), body: "Scrollable recent #{i} " + ("body " * 80)) }
    login_as_browser(users(:one))
    visit room_path(room)
    assert_selector "#messages-container > [id^='message_']", minimum: 10
    page.execute_script <<~JS
      const pane = document.querySelector("#messages")
      pane.scrollTop = 0
      pane.dispatchEvent(new Event("scroll"))
    JS
    assert_selector "a.message-jump-latest", visible: true
    find("a.message-jump-latest").click
    assert_current_path room_path(room), ignore_query: true
    assert_no_selector "a.message-jump-latest", visible: true, wait: 5
  end

  test "invalid upload shows the server's real reason and preserves the composer" do
    login_as_browser(users(:one))
    visit room_path(rooms(:one))
    fill_in "chat-text", with: "Keep unsent content"

    # The MIME is intentionally spoofed: the UI accepts the declared PNG,
    # then Rails must reject its HTML bytes and explain why.
    page.execute_script(<<~JS)
      const fake = new File(["<html>not an image</html>"], "invalid.png", { type: "image/png" })
      const input = document.querySelector("#message_attachments")
      const transfer = new DataTransfer()
      transfer.items.add(fake)
      input.files = transfer.files
      input.dispatchEvent(new Event("change", { bubbles: true }))
    JS
    assert_selector ".composer-previews", text: "invalid.png"
    click_button "Send"
    assert_selector ".composer-feedback.text-danger",
      text: "Attachment content does not match its declared type", wait: 10
    assert_field "chat-text", with: "Keep unsent content"
    assert_selector ".composer-previews", text: "invalid.png"
  end

  test "new messages show a compact jump pill while the reader is scrolled up" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    12.times do |i|
      room.messages.create!(user: bob, body: "Historic scroll #{i} " + ("context " * 65))
    end

    login_as_browser(alice)
    visit room_path(room)
    assert_selector "#messages-container > [id^='message_']", minimum: 10
    fill_in "chat-text", with: "Keep this draft"
    page.execute_script(<<~JS)
      const pane = document.querySelector("#messages")
      pane.scrollTop = 0
      pane.dispatchEvent(new Event("scroll"))
    JS
    assert_selector "a.message-jump-latest", visible: true
    assert_selector 'a.message-jump-latest[data-new-messages="0"]'
    before_scroll = page.evaluate_script('document.querySelector("#messages").scrollTop')

    Capybara.using_session(:pill_sender) do
      login_as_browser(bob)
      visit room_path(room)
      fill_in "chat-text", with: "Fresh message while reading old history"
      click_button "Send"
      assert_selector "#messages-container", text: "Fresh message while reading old history", wait: 10
    end

    assert_selector "#messages-container", text: "Fresh message while reading old history", wait: 15
    assert_selector 'a.message-jump-latest[data-new-messages="1"]', text: "1 new message", wait: 10
    assert_in_delta before_scroll, page.evaluate_script('document.querySelector("#messages").scrollTop'), 3
    assert_field "chat-text", with: "Keep this draft"

    find("a.message-jump-latest").click
    assert_no_selector "a.message-jump-latest", visible: true, wait: 5
    assert_field "chat-text", with: "Keep this draft"
  end

  test "network offline and online events update status without destroying a draft" do
    login_as_browser(users(:one))
    visit room_path(rooms(:one))
    assert_selector '#single_room[data-realtime-health-state="live"]', wait: 15
    fill_in "chat-text", with: "Unsent message must survive network recovery"

    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "onLine", { configurable: true, get: () => false })
      window.dispatchEvent(new Event("offline"))
    JS
    assert_selector '#single_room[data-realtime-health-state="offline"]'
    assert_selector '[data-realtime-health-target="status"]', text: "Offline"
    assert_button "Sync messages", disabled: true

    page.execute_script(<<~JS)
      Object.defineProperty(navigator, "onLine", { configurable: true, get: () => true })
      window.dispatchEvent(new Event("online"))
    JS
    assert_selector '#single_room[data-realtime-health-state="live"]', wait: 10
    assert_field "chat-text", with: "Unsent message must survive network recovery"
    page.execute_script("delete navigator.onLine")
  end

  test "live search replaces stale results and clears without affecting the draft" do
    room = rooms(:one)
    room.messages.create!(user: users(:one), body: "alpha-only needle")
    room.messages.create!(user: users(:one), body: "bravo-only needle")
    initial_count = room.messages.count

    login_as_browser(users(:one))
    visit room_path(room)
    fill_in "chat-text", with: "Draft must stay in composer"
    find('button[aria-label="Search messages"]').click
    fill_in "Search messages", with: "alpha-only"
    assert_selector "#message_search_results .message-search-result", text: "alpha-only needle", wait: 10

    fill_in "Search messages", with: "bravo-only"
    assert_selector "#message_search_results .message-search-result", text: "bravo-only needle", wait: 10
    assert_no_selector "#message_search_results .message-search-result", text: "alpha-only needle"

    within ".message-search-form" do
      find('button[aria-label="Close message search"]').click
    end
    assert_selector '#message-search-panel[hidden]', visible: :all
    assert_selector "turbo-frame#message_search_results[hidden]", visible: :all
    assert_field "Search messages", with: "", visible: :all
    assert_field "chat-text", with: "Draft must stay in composer"
    assert_equal initial_count, room.messages.count
  end

  test "a visible conversation clears its unread badge without a page reload" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    incoming = room.messages.create!(user: bob, body: "Unread from second participant")

    login_as_browser(alice)
    assert_selector "#direct-rooms [data-unread-room-id='#{room.id}']", text: "1"
    within "#direct-rooms" do
      click_link bob.chat_label
    end

    assert_current_path room_path(room), ignore_query: true
    assert_selector "#message_#{incoming.id}", text: incoming.body
    assert_no_selector "#direct-rooms [data-unread-room-id='#{room.id}']", wait: 10
    assert_read_cursor(room: room, user: alice, expected_id: incoming.id)
  end

  test "unread inbox updates live when another user sends and a second tab reads" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")

    login_as_browser(alice)
    visit rooms_path(inbox: "unread")
    assert_selector '#side_panel[data-inbox-sync-connected="true"]', wait: 15
    assert_selector "#direct-rooms", text: "No unread direct messages."
    assert_no_selector "#direct-rooms [data-unread-room-id='#{room.id}']"

    Capybara.using_session(:bob_inbox_sender) do
      login_as_browser(bob)
      visit room_path(room)
      fill_in "chat-text", with: "New unread from another account"
      click_button "Send"
      assert_selector "#messages-container", text: "New unread from another account", wait: 10
    end

    # The first browser is still on Unread, with no F5 or manual reload.
    assert_selector "#direct-rooms [data-unread-room-id='#{room.id}']", text: "1", wait: 15
    assert_selector "#notifications-nav [data-notification-unread-count='1']", wait: 15
    assert_selector "#direct-rooms a[href='#{room_path(room)}']", count: 1

    Capybara.using_session(:alice_second_tab) do
      login_as_browser(alice)
      visit room_path(room)
      assert_selector '#side_panel[data-inbox-sync-connected="true"]', wait: 15
      assert_selector "#messages-container", text: "New unread from another account", wait: 10
      assert_no_selector "#direct-rooms [data-unread-room-id='#{room.id}']", wait: 10
    end

    # A read acknowledgement in one tab invalidates the other tab's list.
    assert_selector "#direct-rooms", text: "No unread direct messages.", wait: 15
    assert_no_selector "#direct-rooms [data-unread-room-id='#{room.id}']"
    assert_no_selector "#notifications-nav [data-notification-unread-count]", wait: 15
    assert_equal room.messages.order(:id).last.id,
      ConversationReadState.find_by!(room: room, user: alice).last_read_message_id
  end

  test "direct conversation starts from user list and stays available to both browsers" do
    alice, bob = users(:one), users(:two)
    room_name = "private_#{[alice.id, bob.id].sort.join('_')}"
    message_text = "Private two-browser delivery check"

    login_as_browser(alice)
    within "#users" do
      click_button bob.chat_label
    end

    # Turbo form submission and 303 navigation are asynchronous in Chrome.
    # Wait for the real browser redirect before querying PostgreSQL.
    assert_current_path %r{\A/rooms/\d+\z}, ignore_query: true, wait: 10
    room = Room.find_by!(name: room_name)
    assert room.is_private?
    assert_equal [alice.id, bob.id].sort, room.participants.pluck(:user_id).sort
    assert_current_path room_path(room), ignore_query: true
    assert_selector "#single_room h4", text: bob.chat_label
    assert_selector "#chat-text"
    assert_selector "#direct-rooms a[href='#{room_path(room)}']", text: bob.chat_label

    Capybara.using_session(:bob) do
      login_as_browser(bob)
      assert_selector "#direct-rooms a[href='#{room_path(room)}']", text: alice.chat_label
      within "#direct-rooms" do
        click_link alice.chat_label
      end
      assert_current_path room_path(room), ignore_query: true
      assert_selector "#chat-text"
      assert_selector "#single_room h4", text: alice.chat_label
    end

    fill_in "chat-text", with: message_text
    click_button "Send"
    assert_text message_text

    Capybara.using_session(:bob) do
      assert_text message_text, wait: 15
      visit rooms_path
      assert_selector "#direct-rooms a[href='#{room_path(room)}']", text: alice.chat_label
      within "#direct-rooms" do
        click_link alice.chat_label
      end
      assert_text message_text
    end

    assert_equal 1, room.messages.where(body: message_text).count
  end

  test "replying quotes the correct room message and keeps existing draft" do
    room = rooms(:one)
    parent = room.messages.create!(user: users(:one), body: "Original context for reply")
    login_as_browser(users(:one))
    visit room_path(room)

    fill_in "chat-text", with: "Unsent draft text"
    within "#message_#{parent.id}" do
      click_button "Message actions"
      click_button "Reply"
    end
    assert_selector ".composer-reply", text: /Original context for reply/
    assert_field "chat-text", with: "Unsent draft text"
    assert_equal parent.id.to_s, find('input[name="message[reply_to_id]"]', visible: :all).value

    click_button "Send"
    assert_selector ".message-quote", text: "Original context for reply", wait: 15
    reply = room.messages.find_by!(body: "Unsent draft text")
    assert_equal parent.id, reply.reply_to_id
    assert_selector "#message_#{reply.id} .message-quote"
    assert_selector ".composer-reply", visible: false
  end

  test "reply to an attachment-only message keeps the quote visible in both browsers" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    original = room.messages.build(user: bob, body: "")
    original.attachments.attach(
      io: StringIO.new("An attachment-only message for reply testing"),
      filename: "original-note.txt",
      content_type: "text/plain"
    )
    original.save!

    login_as_browser(alice)
    visit room_path(room)
    assert_selector "#message_#{original.id} a", text: "original-note.txt"
    Capybara.using_session(:bob) do
      login_as_browser(bob)
      visit room_path(room)
      assert_selector "#message_#{original.id}"
      assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"][connected]',
        visible: :all, wait: 15
    end

    within "#message_#{original.id}" do
      click_button "Message actions"
      click_button "Reply"
    end
    assert_selector ".composer-reply", text: /Reply to .*Attachment/
    assert_equal original.id.to_s, find('input[name="message[reply_to_id]"]', visible: :all).value
    fill_in "chat-text", with: "Replying to the original attachment"
    click_button "Send"
    assert_selector "#messages-container > [id^='message_']",
      text: "Replying to the original attachment", wait: 15

    reply = room.messages.find_by!(body: "Replying to the original attachment")
    assert_equal original.id, reply.reply_to_id
    assert_selector "#message_#{reply.id} .message-quote", text: /Attachment/, wait: 15
    assert_selector ".composer-reply", visible: false

    Capybara.using_session(:bob) do
      assert_selector "#message_#{reply.id} .message-quote", text: /Attachment/, wait: 15
      assert_selector "#message_#{reply.id}", text: "Replying to the original attachment"
    end
  end

  test "two browsers update private message reactions without page reload" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    message = room.messages.create!(user: alice, body: "React to this live")
    login_as_browser(alice)
    visit room_path(room)
    assert_selector "#message_#{message.id}"
    assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"][connected]',
      visible: :all, wait: 15

    Capybara.using_session(:bob) do
      login_as_browser(bob)
      visit room_path(room)
      assert_selector 'turbo-cable-stream-source[channel="RoomMessagesChannel"][connected]',
        visible: :all, wait: 15
      within "#message_#{message.id}" do
        click_button "Message actions"
        find("summary[aria-label='React']").click
        click_button "👍"
      end
      assert_selector "#message_#{message.id} button[aria-label='Remove 👍 reaction']", text: "1", wait: 10
    end

    assert_selector "#message_#{message.id} button[aria-label='React 👍']", text: "1", wait: 15
    within "#message_#{message.id}" do
      find("button[aria-label='React 👍']").click
    end
    assert_selector "#message_#{message.id} button[aria-label='Remove 👍 reaction']", text: "2", wait: 15

    Capybara.using_session(:bob) do
      assert_selector "#message_#{message.id} button[aria-label='Remove 👍 reaction']", text: "2", wait: 15
      within "#message_#{message.id}" do
        find("button[aria-label='Remove 👍 reaction']").click
      end
      assert_selector "#message_#{message.id} button[aria-label='React 👍']", text: "1", wait: 15
    end

    assert_selector "#message_#{message.id} button[aria-label='Remove 👍 reaction']", text: "1", wait: 15
    assert_equal 1, message.message_reactions.reload.count
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
        await window.__audioContext.resume()
        return window.__audioOut.stream
      }
    JS
    click_button "Record voice message"
    assert_selector ".composer-voice", visible: true
    assert_equal true, page.evaluate_script("window.__voiceRequestedAudio")
    sleep 1.6
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
      # <source> has no independent rendered box; inspect it in DOM, not visibility.
      assert_selector "#message_#{message.id} audio source[type='audio/webm']", visible: :all
    end
  end

  test "recorded silent VP8 video is previewed, sent, and visible to second browser" do
    alice, bob = users(:one), users(:two)
    room = Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
    login_as_browser(alice)
    visit room_path(room)

    # Chrome Canvas.captureStream gives actual VP8 encoder frames without
    # requiring a physical camera in CI (Linux Mint hardware checked by owner).
    page.execute_script <<~JS
      const canvas = document.createElement("canvas")
      canvas.width = 320
      canvas.height = 180
      const context = canvas.getContext("2d")
      let frame = 0
      window.__videoTimer = setInterval(() => {
        context.fillStyle = frame++ % 2 ? "#152d4c" : "#285b72"
        context.fillRect(0, 0, 320, 180)
      }, 55)
      window.__syntheticVideo = canvas.captureStream(15)
      navigator.mediaDevices.getUserMedia = async (options) => {
        window.__videoAudioRequested = Boolean(options.audio)
        return window.__syntheticVideo
      }
    JS

    click_button "Take photo"
    assert_selector ".composer-camera", visible: true
    assert_equal false, page.evaluate_script("window.__videoAudioRequested")
    click_button "Record silent video"
    assert_selector ".composer-camera", text: /Recording video/
    sleep 1.6
    click_button "Stop video"
    assert_selector ".composer-preview video[controls]", wait: 12
    assert_selector ".composer-preview", text: /clip-\d+\.webm/
    click_button "Send"

    assert_selector ".video-message video[controls]", wait: 15
    message = room.messages.order(:id).last
    assert_equal 1, message.attachments.count
    assert_equal "video/webm", message.attachments.first.blob.content_type

    Capybara.using_session(:bob) do
      login_as_browser(bob)
      visit room_path(room)
      assert_selector "#message_#{message.id} .video-message video[controls]", wait: 15
      assert_selector "#message_#{message.id} video source[type='video/webm']", visible: :all
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
      click_button "Message actions"
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
      click_button "Message actions"
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

  def assert_presence_session_count(room:, user:, expected:)
    key = "turbo-chat:#{Rails.env}:presence:v1:room:#{room.id}:user:#{user.id}:sessions"
    redis = Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/4"))
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 5
    count = nil
    loop do
      count = redis.zcard(key)
      break if count == expected
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
    assert_equal expected, count, "Expected server-confirmed presence session count"
  ensure
    redis&.close
  end

  def assert_read_cursor(room:, user:, expected_id:)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 8
    loop do
      state = ConversationReadState.find_by(room: room, user: user)
      break if state&.last_read_message_id == expected_id
      break if Process.clock_gettime(Process::CLOCK_MONOTONIC) >= deadline

      sleep 0.05
    end
    assert_equal expected_id,
      ConversationReadState.find_by(room: room, user: user)&.last_read_message_id,
      "Expected persisted read cursor after asynchronous browser acknowledgement"
  end

  def csrf_token_from(html)
    token = html.match(/<meta name="csrf-token" content="([^"]+)"/)&.captures&.first
    assert token.present?, "Expected a Rails CSRF meta token in authenticated HTML"
    CGI.unescapeHTML(token)
  end

  def login_as_browser(user)
    # Capybara named sessions (e.g. :bob) can survive between system tests.
    # Reset only this browser context before signing in to prevent Devise
    # redirecting an already-authenticated session away from the login form.
    Capybara.current_session.reset!
    # The Chrome process outlives some named sessions. Establish our local
    # domain, then clear its actual browser cookies before the Devise login.
    # Clicking a Turbo-powered Log out and immediately navigating races the
    # DELETE response and intermittently redirects to an authenticated page.
    visit root_path
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    assert_field "Email", wait: 5
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
    visit rooms_path
    assert_current_path rooms_path, ignore_query: true
  end
end
