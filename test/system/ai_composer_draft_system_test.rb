require "application_system_test_case"

class AiComposerDraftSystemTest < ApplicationSystemTestCase
  def login_user(user)
    Capybara.current_session.reset!
    visit root_path
    page.execute_script("Object.keys(window.localStorage).filter(k => k.startsWith('turbo-chat:writing:v1:user:')).forEach(k => window.localStorage.removeItem(k))")
    page.driver.browser.manage.delete_all_cookies
    visit new_user_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: "test-password-123"
    click_button "Log in"
    assert_current_path root_path, ignore_query: true, wait: 10
  end

  def dm_for(alice, bob)
    Room.create_private_room([alice, bob], "private_#{[alice.id, bob.id].sort.join('_')}")
  end

  test "offline AI panel never sends, renders input inertly, and preserves draft reply and file" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    parent = room.messages.create!(user: eric, body: "A message to reply to")
    login_user(jack)
    visit room_path(room)
    within "#message_#{parent.id}" do
      click_button "Message actions"
      click_button "Reply"
    end
    original = "Review my <img src=x onerror=alert(1)> draft"
    fill_in "chat-text", with: original
    fixture = Rails.root.join("test/fixtures/files/upload_note.txt")
    attach_file "message_attachments", fixture, make_visible: true
    assert_selector ".composer-preview", text: "upload_note.txt"
    original_reply = find('input[name="message[reply_to_id]"]', visible: :all).value
    assert_equal parent.id.to_s, original_reply
    count = room.messages.count

    click_button "Edit unsent message"
    assert_selector "#ai-draft-panel:not([hidden])", wait: 10
    assert_field "Editable working copy", with: original
    assert_no_selector "#ai-draft-panel img"
    assert_equal false, page.evaluate_script("!!window.__xss")
    find("#ai-draft-panel summary.sd-ai-style-summary").click
    assert_selector ".sd-ai-draft-presets button", count: 6
    click_button "Friendly"
    assert_selector ".sd-ai-draft-presets button[data-preset-id='friendly'][aria-pressed='true']"
    assert_selector "#ai-draft-panel", text: "Preset saved locally"
    assert_field "Editable working copy", with: original
    click_button "Reload from message"
    assert_field "Editable working copy", with: original
    assert_field "chat-text", with: original
    assert_equal original_reply, find('input[name="message[reply_to_id]"]', visible: :all).value
    assert_selector ".composer-preview", text: "upload_note.txt"
    assert_equal "upload_note.txt", page.evaluate_script("document.querySelector('#message_attachments').files[0].name")
    assert_equal count, room.messages.count

    click_button "Close draft review"
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_field "chat-text", with: original
    assert_equal original_reply, find('input[name="message[reply_to_id]"]', visible: :all).value
    assert_selector ".composer-preview", text: "upload_note.txt"
    assert_equal "ai-draft-toggle", page.evaluate_script("document.activeElement.id")
    assert_equal count, room.messages.count
  end

  test "empty and oversized drafts fail closed; editing invalidates preview and Escape restores focus" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    login_user(jack)
    visit room_path(room)
    count = room.messages.count

    click_button "Edit unsent message"
    assert_selector "#ai-draft-panel", text: /Type a message first/
    assert_selector "#ai-draft-panel .sd-ai-draft-result[hidden]", visible: :all
    fill_in "chat-text", with: "My local safe text"
    click_button "Reload from message"
    assert_field "Editable working copy", with: "My local safe text"
    fill_in "chat-text", with: "Updated unsent text"
    assert_field "Editable working copy", with: "Updated unsent text"
    click_button "Reload from message"
    assert_field "Editable working copy", with: "Updated unsent text"

    fill_in "chat-text", with: "x" * 5_001
    click_button "Reload from message"
    assert_selector "#ai-draft-panel", text: /up to 5,000 characters/
    assert_selector "#ai-draft-panel .sd-ai-draft-result[hidden]", visible: :all
    find("#ai-draft-panel .sd-ai-draft-refresh").send_keys(:escape)
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_field "chat-text", with: "x" * 5_001
    assert_equal "ai-draft-toggle", page.evaluate_script("document.activeElement.id")
    assert_equal count, room.messages.count
  end


  test "working copy applies and undoes without sending or changing reply and attachments" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    message = room.messages.create!(user: eric, body: "Please respond")
    login_user(jack)
    visit room_path(room)
    within "#message_#{message.id}" do
      click_button "Message actions"
      click_button "Reply"
    end
    fill_in "chat-text", with: "How you deals"
    fixture = Rails.root.join("test/fixtures/files/upload_note.txt")
    attach_file "message_attachments", fixture, make_visible: true
    count = room.messages.count

    click_button "Edit unsent message"
    assert_field "Editable working copy", with: "How you deals"
    fill_in "Editable working copy", with: "How are you doing?"
    assert_button "Apply to message", disabled: false
    assert_field "chat-text", with: "How you deals"
    click_button "Apply to message"
    assert_field "chat-text", with: "How are you doing?"
    assert_selector ".composer-preview", text: "upload_note.txt"
    assert_equal message.id.to_s, find('input[name="message[reply_to_id]"]', visible: :all).value
    assert_equal count, room.messages.count

    click_button "Undo applied edit"
    assert_field "chat-text", with: "How you deals"
    assert_equal count, room.messages.count
    fill_in "Editable working copy", with: "How are things going?"
    click_button "Apply to message"
    fill_in "chat-text", with: "Human typing wins"
    assert_selector "#ai-draft-panel button.sd-ai-draft-undo[hidden]", visible: :all
    assert_field "chat-text", with: "Human typing wins"
    assert_equal count, room.messages.count
  end

  test "a stale working copy cannot overwrite a newer message draft" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    login_user(jack)
    visit room_path(room)
    fill_in "chat-text", with: "First wording"
    click_button "Edit unsent message"
    fill_in "Editable working copy", with: "Proposed replacement"
    fill_in "chat-text", with: "Newer human wording"
    assert_button "Apply to message", disabled: true
    assert_selector "#ai-draft-panel", text: /Reload the copy before applying/
    assert_field "chat-text", with: "Newer human wording"
    click_button "Reload from message"
    assert_field "Editable working copy", with: "Newer human wording"
    assert_button "Apply to message", disabled: true
  end


  test "per-room writing preferences persist in this browser and never activate unavailable AI" do
    jack, eric = users(:one), users(:two)
    first = dm_for(jack, eric)
    second = Room.create!(name: "Separate settings room", kind: "private_group",
      is_private: true, owner: jack)
    second.participants.create!(user: jack, group_role: "owner")
    login_user(jack)
    visit room_path(first)

    assert_selector ".sd-ai-room-strip", text: "AI OFF"
    assert_selector ".sd-ai-room-strip", text: "AUTO OFF"
    assert_selector ".sd-ai-room-strip", text: "SPELL ON"
    assert_selector ".sd-ai-room-preset", text: "Polish / Clarity"
    assert_equal "true", find("#chat-text")[:spellcheck]

    assert_no_selector "#ai-room-settings-toggle", visible: :all
    click_button "Edit unsent message"
    click_button "Room settings"
    assert_selector "#ai-room-settings:not([hidden])"
    assert_selector "#ai-room-settings .sd-ai-room-context", text: eric.chat_label
    assert_selector "#ai-room-settings .sd-ai-room-context", text: /Chrome · this device/
    assert_selector "#ai-room-settings .sd-ai-room-group", count: 2
    assert_selector "#ai-room-settings button[aria-label='Auto correction unavailable'][role='switch'][aria-checked='false']"
    find("button.sd-ai-room-switch--locked[aria-checked='false']").click
    assert_selector "#ai-room-settings", text: /No text is corrected automatically/
    assert_selector ".sd-ai-room-strip", text: "AUTO OFF"

    within "#ai-room-settings" do
      click_button "Friendly"
      find("button[data-ai-draft-target='spellToggle'][role='switch']").click
    end
    assert_selector ".sd-ai-room-preset", text: "Friendly"
    assert_selector ".sd-ai-room-strip", text: "SPELL OFF"
    assert_equal "false", find("#chat-text")[:spellcheck]
    saved = page.evaluate_script(
      "JSON.parse(localStorage.getItem('turbo-chat:writing:v1:user:#{jack.id}:room:#{first.id}'))"
    )
    assert_equal({ "preset" => "friendly", "spellcheck" => false }, saved)
    within "#ai-room-settings" do
      find("button[data-preset-id='friendly']").send_keys(:escape)
    end
    assert_selector "#ai-room-settings[hidden]", visible: :all
    assert_equal "ai-draft-toggle", page.evaluate_script("document.activeElement.id")

    visit room_path(first)
    assert_selector ".sd-ai-room-preset", text: "Friendly"
    assert_selector ".sd-ai-room-strip", text: "SPELL OFF"
    assert_selector ".sd-ai-room-strip", text: "AUTO OFF"
    assert_equal "false", find("#chat-text")[:spellcheck]
    fill_in "chat-text", with: "Unsent local text"
    click_button "Edit unsent message"
    find("#ai-draft-panel summary.sd-ai-style-summary").click
    assert_selector "#ai-draft-panel button[data-preset-id='friendly'][aria-pressed='true']"
    assert_equal "false", find("#ai-draft-edit")[:spellcheck]

    visit room_path(second)
    assert_selector ".sd-ai-room-preset", text: "Polish / Clarity"
    assert_selector ".sd-ai-room-strip", text: "SPELL ON"
    assert_selector ".sd-ai-room-strip", text: "AUTO OFF"
    assert_equal "true", find("#chat-text")[:spellcheck]
    assert_nil page.evaluate_script(
      "localStorage.getItem('turbo-chat:writing:v1:user:#{jack.id}:room:#{second.id}')"
    )
    visit room_path(first)
    assert_selector ".sd-ai-room-preset", text: "Friendly"
    assert_selector ".sd-ai-room-strip", text: "SPELL OFF"
  end

  test "one AI icon switches editor and settings without discarding un-applied edits" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    login_user(jack)
    visit room_path(room)
    fill_in "chat-text", with: "An unprocessed unsent text"
    count = room.messages.count

    assert_selector "#ai-draft-toggle", count: 1
    assert_no_selector "#ai-room-settings-toggle", visible: :all
    click_button "Edit unsent message"
    assert_selector "#ai-draft-panel:not([hidden])"
    assert_selector "#ai-room-settings[hidden]", visible: :all
    fill_in "Editable working copy", with: "My revised but unsent text"

    within "#ai-draft-panel" do
      click_button "Room settings"
    end
    assert_selector "#ai-room-settings:not([hidden])"
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_selector "#ai-room-settings .sd-ai-room-context", text: eric.chat_label
    within "#ai-room-settings" do
      click_button "Friendly"
      click_button "Edit draft"
    end
    assert_selector "#ai-draft-panel:not([hidden])"
    assert_field "Editable working copy", with: "My revised but unsent text"
    assert_field "chat-text", with: "An unprocessed unsent text"
    click_button "Apply to message"
    assert_field "chat-text", with: "My revised but unsent text"
    assert_equal count, room.messages.count
    click_button "Undo applied edit"
    assert_field "chat-text", with: "An unprocessed unsent text"
    assert_equal count, room.messages.count
    click_button "Close draft review"
    assert_selector "#ai-room-settings[hidden]", visible: :all
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_equal "ai-draft-toggle", page.evaluate_script("document.activeElement.id")
  end

  test "room preferences never write or auto-process messages and preserve attachments" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    login_user(jack)
    visit room_path(room)
    fill_in "chat-text", with: "This is my private unsent draft"
    attach_file "message_attachments", Rails.root.join("test/fixtures/files/upload_note.txt"), make_visible: true
    original_count = room.messages.count

    assert_no_selector "#ai-room-settings-toggle", visible: :all
    click_button "Edit unsent message"
    click_button "Room settings"
    within "#ai-room-settings" do
      click_button "Concise"
      find("button.sd-ai-room-switch--locked[aria-checked='false']").click
    end
    assert_selector ".sd-ai-room-strip", text: "AI OFF"
    assert_selector ".sd-ai-room-strip", text: "AUTO OFF"
    assert_field "chat-text", with: "This is my private unsent draft"
    assert_selector ".composer-preview", text: "upload_note.txt"
    assert_equal original_count, room.messages.count
    stored = page.evaluate_script(
      "localStorage.getItem('turbo-chat:writing:v1:user:#{jack.id}:room:#{room.id}')"
    )
    assert_not_includes stored, "private unsent draft"
    assert_not_includes stored, "attachment"
  end

  test "a successful explicit Send closes stale AI preview but follows normal message path" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    login_user(jack)
    visit room_path(room)
    fill_in "chat-text", with: "Only the ordinary Send action persists this"
    click_button "Edit unsent message"
    assert_field "Editable working copy", with: "Only the ordinary Send action persists this"
    assert_difference("Message.count", 1) do
      click_button "Send"
      assert_selector "#messages-container", text: "Only the ordinary Send action persists this", wait: 15
    end
    assert_selector "#ai-draft-panel[hidden]", visible: :all
    assert_field "chat-text", with: ""
  end
  test "writing panels stay bounded on desktop and inside the narrow mobile viewport" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    page.current_window.resize_to(1440, 900)
    login_user(jack)
    visit room_path(room)
    fill_in "chat-text", with: "A draft that must remain unchanged"
    before = room.messages.count

    click_button "Edit unsent message"
    assert_selector "#ai-draft-panel:not([hidden])"
    editor_width = page.evaluate_script(
      "document.querySelector('#ai-draft-panel').getBoundingClientRect().width"
    )
    assert_operator editor_width, :<=, 526
    assert_equal "0px", page.evaluate_script(
      "getComputedStyle(document.querySelector('#ai-draft-panel')).borderTopWidth")

    within "#ai-draft-panel" do
      click_button "Room settings"
    end
    assert_selector "#ai-room-settings:not([hidden])"
    desktop_metrics = page.evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector('#ai-room-settings').getBoundingClientRect()
        const hint = document.querySelector('.sd-ai-room-option--auto p')
        return {
          width: rect.width,
          left: rect.left,
          right: rect.right,
          viewport: window.innerWidth,
          hintSize: parseFloat(getComputedStyle(hint).fontSize)
        }
      })()
    JS
    assert_operator desktop_metrics["width"], :<=, 456
    assert_equal "0px", page.evaluate_script(
      "getComputedStyle(document.querySelector('#ai-room-settings')).borderTopWidth")
    assert_operator desktop_metrics["left"], :>=, 0
    assert_operator desktop_metrics["right"], :<=, desktop_metrics["viewport"] + 1
    assert_operator desktop_metrics["hintSize"], :>=, 11

    page.current_window.resize_to(390, 844)
    mobile_metrics = page.evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector('#ai-room-settings').getBoundingClientRect()
        return { width: rect.width, left: rect.left, right: rect.right, viewport: window.innerWidth, scrollHeight: document.querySelector("#ai-room-settings").scrollHeight, clientHeight: document.querySelector("#ai-room-settings").clientHeight }
      })()
    JS
    assert_operator mobile_metrics["width"], :>=, 260
    assert_operator mobile_metrics["left"], :>=, -1
    assert_operator mobile_metrics["right"], :<=, mobile_metrics["viewport"] + 1
    assert_selector "#ai-room-settings .sd-ai-room-context", text: eric.chat_label
    assert_operator mobile_metrics["scrollHeight"], :<=, mobile_metrics["clientHeight"] + 2,
      "Room settings should not need an inner scrollbar at a normal mobile height"
    assert_selector "#ai-room-settings #ai-room-style-title .sd-icon", count: 1

    within "#ai-room-settings" do
      click_button "Edit draft"
    end
    assert_selector "#ai-draft-panel:not([hidden])"
    mobile_editor = page.evaluate_script(<<~JS)
      (() => {
        const rect = document.querySelector('#ai-draft-panel').getBoundingClientRect()
        return { left: rect.left, right: rect.right, viewport: window.innerWidth, scrollHeight: document.querySelector("#ai-draft-panel").scrollHeight, clientHeight: document.querySelector("#ai-draft-panel").clientHeight }
      })()
    JS
    assert_operator mobile_editor["left"], :>=, -1
    assert_operator mobile_editor["right"], :<=, mobile_editor["viewport"] + 1
    assert_operator mobile_editor["scrollHeight"], :<=, mobile_editor["clientHeight"] + 2,
      "Draft editor should not need an inner scrollbar at a normal mobile height"
    assert_selector "#ai-draft-panel .sd-ai-style-summary .sd-icon", count: 1
    assert_field "chat-text", with: "A draft that must remain unchanged"
    assert_equal before, room.messages.count
  ensure
    # Selenium/Capybara may reuse Chrome across test scenarios. An intentionally
    # narrow viewport must not leak into unrelated desktop navigation tests.
    page.current_window.resize_to(1400, 1000)
  end

end
