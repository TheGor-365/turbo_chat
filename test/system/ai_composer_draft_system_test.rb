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
    assert_selector "#ai-draft-panel .sd-ai-style-summary", text: "Friendly"
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
    assert_selector "#ai-draft-panel .sd-ai-provider-details", text: /For draft editing, write your own message first/, visible: :all
    assert_selector "#ai-draft-panel .sd-ai-draft-feedback:empty", visible: :all
    assert_selector "#ai-draft-panel .sd-ai-draft-result[hidden]", visible: :all
    page.execute_script("document.querySelector('#chat-text').value = 'My local safe text'; document.querySelector('#chat-text').dispatchEvent(new Event('input', { bubbles: true }))")
    click_button "Reload from message"
    assert_field "Editable working copy", with: "My local safe text"
    page.execute_script("document.querySelector('#chat-text').value = 'Updated unsent text'; document.querySelector('#chat-text').dispatchEvent(new Event('input', { bubbles: true }))")
    assert_field "Editable working copy", with: "Updated unsent text"
    click_button "Reload from message"
    assert_field "Editable working copy", with: "Updated unsent text"

    page.execute_script("document.querySelector('#chat-text').value = 'x'.repeat(5001); document.querySelector('#chat-text').dispatchEvent(new Event('input', { bubbles: true }))")
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
    # A native modal deliberately prevents typing into the composer behind it.
    # Model an out-of-band edit to verify that newer content invalidates Undo.
    page.execute_script(<<~JS)
      const composer = document.querySelector('#chat-text')
      composer.value = 'Human typing wins'
      composer.dispatchEvent(new Event('input', { bubbles: true }))
    JS
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
    page.execute_script("document.querySelector('#chat-text').value = 'Newer human wording'; document.querySelector('#chat-text').dispatchEvent(new Event('input', { bubbles: true }))")
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
    assert_selector "#ai-room-settings", text: /Automatic correction is off/
    assert_selector ".sd-ai-room-strip", text: "AUTO OFF"

    within "#ai-room-settings" do
      find("summary.sd-ai-room-style-summary").click
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
      find("summary.sd-ai-room-style-summary").click
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
      find("summary.sd-ai-room-style-summary").click
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
    click_button "Close draft review"
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
    assert_equal "dialog", find("#ai-draft-panel").tag_name
    assert_equal true, page.evaluate_script("document.querySelector('#ai-draft-panel').open")
    assert_selector ".sd-ai-sheet-backdrop:not([hidden])"
    editor_width = page.evaluate_script(
      "document.querySelector('#ai-draft-panel').getBoundingClientRect().width"
    )
    room_width = page.evaluate_script("document.querySelector('#room_container').getBoundingClientRect().width")
    assert_operator editor_width, :<=, room_width
    assert_operator editor_width, :>=, room_width - 56
    editor_height = page.evaluate_script("document.querySelector('#ai-draft-panel').getBoundingClientRect().height")
    assert_operator editor_height, :<, 650
    assert_equal "0px", page.evaluate_script(
      "getComputedStyle(document.querySelector('#ai-draft-panel')).borderTopWidth")

    within "#ai-draft-panel" do
      click_button "Room settings"
    end
    assert_selector "#ai-room-settings:not([hidden])"
    assert_equal "dialog", find("#ai-room-settings").tag_name
    assert_equal true, page.evaluate_script("document.querySelector('#ai-room-settings').open")
    assert_equal false, page.evaluate_script("document.querySelector('#ai-draft-panel').open")
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
    assert_operator desktop_metrics["width"], :<=, room_width
    assert_operator desktop_metrics["width"], :>=, room_width - 56
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
    assert_operator mobile_metrics["width"], :>=, 350
    assert_operator mobile_metrics["left"], :>=, -1
    assert_operator mobile_metrics["right"], :<=, mobile_metrics["viewport"] + 1
    assert_selector "#ai-room-settings .sd-ai-room-context", text: eric.chat_label
    # A viewport sheet intentionally contains its own single scroll when larger
    # icon targets and writing options exceed a short mobile viewport.
    assert_operator mobile_metrics["clientHeight"], :<=, 824
    assert_equal "auto", page.evaluate_script(
      "getComputedStyle(document.querySelector('#ai-room-settings')).overflowY")
    assert_equal "true", page.evaluate_script(
      "document.body.classList.contains('sd-ai-sheet-open').toString()")
    assert_selector "#ai-room-settings section.sd-ai-room-group--style[aria-label='Preferred writing style']"
    assert_no_selector "#ai-room-settings .sd-ai-room-group--style h4", visible: :all
    assert_no_selector "#ai-room-settings", text: "Only style/spelling settings stay here."

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
    assert_operator mobile_editor["clientHeight"], :<=, 824
    assert_equal "auto", page.evaluate_script(
      "getComputedStyle(document.querySelector('#ai-draft-panel')).overflowY")
    assert_selector "#ai-draft-panel .sd-ai-style-summary .sd-icon", count: 1
    assert_field "chat-text", with: "A draft that must remain unchanged"
    assert_equal before, room.messages.count
  ensure
    # Selenium/Capybara may reuse Chrome across test scenarios. An intentionally
    # narrow viewport must not leak into unrelated desktop navigation tests.
    page.current_window.resize_to(1400, 1000)
  end

  test "local preview renders the editable Markdown draft without a provider or a Send" do
    jack, eric = users(:one), users(:two)
    room = dm_for(jack, eric)
    text = "# Review\n- Check **Rails** [M999999]\n<script>window.__unsafePreview = true</script>"
    login_user(jack)
    visit room_path(room)
    fill_in "chat-text", with: text
    before = room.messages.count
    click_button "Edit unsent message"
    click_button "Preview locally"
    assert_selector "#ai-draft-panel .sd-ai-deliverable-preview[open]"
    assert_selector "#ai-draft-panel .sd-ai-deliverable-preview h4", text: "Review"
    assert_selector "#ai-draft-panel .sd-ai-deliverable-preview li strong", text: "Rails"
    assert_selector "#ai-draft-panel .sd-ai-deliverable-preview", text: "<script>window.__unsafePreview = true</script>"
    assert_no_selector "#ai-draft-panel .sd-ai-deliverable-preview script, #ai-draft-panel .sd-ai-deliverable-preview a", visible: :all
    assert_nil page.evaluate_script("window.__unsafePreview")
    assert_field "chat-text", with: text
    assert_equal before, room.messages.count

    fill_in "Editable working copy", with: "# Revised\n- Inspect logs"
    assert_selector "#ai-draft-panel .sd-ai-deliverable-preview h4", text: "Revised"
    click_button "Apply to message"
    assert_field "chat-text", with: "# Revised\n- Inspect logs"
    assert_equal before, room.messages.count
  end

end
